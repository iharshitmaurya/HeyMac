import AppKit
import AVFoundation
import CoreGraphics
import Observation
import SwiftUI
import HeyMacCore
import HeyMacEngine

private final class SetupWorkToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Conditional setup, with cancellable capture and an encrypted, uncommitted replacement identity.
@MainActor @Observable
final class SetupFlow {
    enum Step: Int, CaseIterable { case welcome, camera, enroll, test, accessibility, password, apps, done }
    enum Plan: String, CaseIterable {
        case both = "Lock Screen and App Lock", lock = "Lock Screen", apps = "App Lock"
        var detail: String {
            switch self {
            case .both: return "Set up both ways to use Hey Mac."
            case .lock: return "Unlock your Mac when you wake the screen."
            case .apps: return "Keep selected apps private."
            }
        }
    }
    let model: AppModel
    var step: Step
    let startStep: Step
    var plan = Plan.both
    private var advanceTask: Task<Void, Never>?
    private var passwordTask: Task<Void, Never>?
    private var work: SetupWorkToken?
    private var worker: Task<Void, Never>?
    var stopping = false
    private var enrollment: EnrollmentSession?
    private var closed = false
    var cameraAuthorized = false
    var cameraDenied = false
    var enrolling = false
    var samplesCaptured = 0
    var sampleTarget = 8
    var enrollHint = ""
    var enrollFinished = false
    enum HintTone { case neutral, good, warn }
    var enrollHintTone = HintTone.neutral
    var testing = false
    var testMessage: String?
    var testPassed = false
    var password = ""
    var passwordConfirm = ""
    var passwordMessage: String?
    var savingPassword = false
    var appSearch = ""
    var availableApps: [InstalledApp] = []
    var preview: CGImage?
    private var previewTimer: Timer?
    private var previewSequence = 0

    init(model: AppModel, startAt step: Step) {
        self.model = model; self.step = step; startStep = step
        refreshCameraStatus()
        if step == .enroll || step == .test { startPreview() }
    }

    var standaloneTest: Bool { startStep == .test }
    var wantsLockScreen: Bool { plan != .apps }
    var wantsAppLock: Bool { plan != .lock }
    var activeSteps: [Step] {
        if standaloneTest { return [.test] }
        if startStep == .enroll { return [.enroll, .test, .done] }
        return [.welcome, .camera, .enroll, .test] + (wantsLockScreen ? [.accessibility, .password] : []) + (wantsAppLock ? [.apps] : []) + [.done]
    }
    var stepIndex: Int { activeSteps.firstIndex(of: step) ?? 0 }
    var title: String {
        switch step {
        case .welcome: return "Choose features"
        case .camera: return "Allow Camera Access"
        case .enroll: return "Set Up Face Recognition"
        case .test: return "Test Face Recognition"
        case .accessibility: return "Allow Accessibility Access"
        case .password: return "Finish Lock Screen Setup"
        case .apps: return "Choose Apps to Protect"
        case .done: return "Here’s what’s ready"
        }
    }
    var working: Bool { enrolling || testing || savingPassword || stopping }
    var canGoBack: Bool { stepIndex > 0 && !working && step != .done }

    func refreshCameraStatus() {
        if AppModel.uiSnapshotMode { cameraAuthorized = true; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorized = status == .authorized
        cameraDenied = status == .denied || status == .restricted
        model.refreshSystemState()
    }
    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { [weak self] in
                guard let self, !closed else { return }
                refreshCameraStatus()
                if granted && step == .camera { advance() }
            }
        }
    }
    func startPreview() {
        guard previewTimer == nil, let runtime = model.runtime else { return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let frame = runtime.camera.frame(newerThan: self.previewSequence) else { return }
                self.previewSequence = frame.sequence; self.preview = frame.image
            }
        }
    }
    func stopPreview() { previewTimer?.invalidate(); previewTimer = nil; preview = nil }

    func startEnrollment() {
        guard !working else { return }
        guard let runtime = model.runtime else {
            enrollHint = model.startupError ?? "Face recognition is unavailable. Try reopening Hey Mac."
            enrollHintTone = .warn
            return
        }
        model.beginFaceSetup()
        work?.cancel()
        let token = SetupWorkToken(); work = token
        let session = runtime.makeEnrollmentSession(strictness: model.strictness)
        enrollment = session
        enrolling = true; enrollFinished = false; testPassed = false; testMessage = nil
        samplesCaptured = 0; sampleTarget = session.enroller.target
        enrollHint = "Hold still and look straight at the camera."; enrollHintTone = .neutral
        startPreview()
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            session.enroller.run(shouldContinue: { token.isActive }) { progress in
                Task { @MainActor [weak self] in
                    guard let self, token.isActive, !closed else { return }
                    apply(progress)
                }
            }
            await MainActor.run { [weak self] in
                guard let self, token.isActive else { return }
                enrolling = false
            }
        }
    }
    private func apply(_ progress: EnrollmentProgress) {
        switch progress {
        case .sampleCaptured(let count, let target, _):
            samplesCaptured = count; sampleTarget = target
            enrollHint = "Keep looking at the camera…"; enrollHintTone = .neutral
        case .rejectedNotLive:
            enrollHint = "Face the camera in even lighting. Use your real face, without photos or screens."; enrollHintTone = .warn
        case .finished(let minAgreement, _, _):
            enrollFinished = true
            model.log.write(String(format: "enrolled with minimum sample agreement %.3f", minAgreement))
            enrollHint = "Samples captured. Test recognition before saving."; enrollHintTone = .good
            advanceTask?.cancel()
            advanceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self, !closed, step == .enroll else { return }
                advance()
            }
        case .failed(let message): enrollHint = message; enrollHintTone = .warn
        }
    }
    func runTest() {
        guard !working else { return }
        guard let runtime = model.runtime else {
            testMessage = model.startupError ?? "Face recognition is unavailable. Try reopening Hey Mac."
            return
        }
        model.beginFaceSetup()
        let token = SetupWorkToken(); work = token
        let session = enrollment
        let verifier = session?.verifier ?? runtime.verifier(interactive: true, strictness: model.strictness)
        testing = true; testMessage = nil; testPassed = false; startPreview()
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = verifier.run(timeout: 8, requiredConsecutive: 2, waitForTurn: 1, keepGoing: { token.isActive })
            await MainActor.run { [weak self] in
                guard let self, token.isActive, !closed else { return }
                testing = false
                do {
                    if outcome.matched {
                        try session?.commit()
                        if session != nil { model.acceptFaceSetup(); enrollment = nil }
                        testPassed = true; testMessage = "Face recognition was tested successfully."
                    } else {
                        testMessage = outcome.failure ?? "Face not recognized. Face the camera in even lighting, then try again."
                    }
                } catch { testMessage = "Could not save face setup. Your previous face data is unchanged. Try again." }
                model.log.write("setup test: \(outcome.summary)")
            }
        }
    }
    func cancelWork() {
        guard !stopping else { return }
        if enrolling || testing {
            stopping = true
            let previous = worker
            Task { @MainActor in await previous?.value; stopping = false }
        }
        work?.cancel(); work = nil; advanceTask?.cancel(); passwordTask?.cancel(); savingPassword = false
        enrolling = false; testing = false
        enrollHint = "Capture stopped. You can try again."; enrollHintTone = .neutral
        testMessage = "Recognition stopped. You can try again."
    }
    func saveLoginPassword() {
        guard !savingPassword else { return }
        guard !password.isEmpty else { passwordMessage = "Enter your Mac login password."; return }
        guard password == passwordConfirm else { passwordMessage = "The two passwords don’t match."; return }
        savingPassword = true
        let value = password
        passwordTask = Task { @MainActor in
            let error = await model.saveLoginPassword(value)
            savingPassword = false
            guard !closed, !Task.isCancelled else { return }
            if let error { passwordMessage = error; return }
            password = ""; passwordConfirm = ""; passwordMessage = "Password saved."
            advance()
        }
    }
    func restartEnrollment() {
        guard !working else { return }
        if standaloneTest { close(); model.reEnroll(); return }
        advanceTask?.cancel(); enrollment = nil
        enrollFinished = false; samplesCaptured = 0; enrollHint = ""; testPassed = false; testMessage = nil
        step = .enroll; startPreview()
    }
    func back() {
        guard canGoBack else { return }
        move(to: activeSteps[stepIndex - 1])
    }
    func advance() {
        guard let index = activeSteps.firstIndex(of: step), index + 1 < activeSteps.count else { return }
        move(to: activeSteps[index + 1])
    }
    private func move(to next: Step) {
        advanceTask?.cancel(); step = next
        if next == .enroll || next == .test { startPreview() } else { stopPreview() }
        if next == .apps { availableApps = InstalledApps.scan() }
    }
    func finishLater() { cancelWork(); finish() }
    func finish() {
        guard !closed else { return }
        if startStep == .welcome {
            if wantsLockScreen && model.setupComplete && model.cameraAuthorized && model.accessibilityTrusted && model.hasSavedPassword && !model.lockScreenNeedsPassword { model.setLockScreenEnabled(true) }
            if wantsAppLock && !model.appLockApps.isEmpty { model.setAppLockEnabled(true) }
        }
        model.finishSetup()
        model.openSettings()
    }
    func close() { model.windows.close(id: "setup") }
    func teardown() {
        guard !closed else { return }
        closed = true; work?.cancel(); advanceTask?.cancel(); passwordTask?.cancel(); stopPreview()
        enrollment = nil; password = ""; passwordConfirm = ""
        model.endFaceSetup()
    }
}
