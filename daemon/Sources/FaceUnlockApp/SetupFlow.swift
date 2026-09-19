import AppKit
import AVFoundation
import CoreGraphics
import Observation
import SwiftUI
import FaceUnlockCore
import FaceUnlockEngine

/// State and actions behind the setup window.
@MainActor
@Observable
final class SetupFlow {
    enum Step: Int, CaseIterable {
        case welcome, camera, enroll, test, features, done
    }

    let model: AppModel
    var step: Step
    /// The step the window opened on; Back never goes before it (the Test window opens mid-flow).
    let startStep: Step
    private var advanceTask: Task<Void, Never>?

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

    var preview: CGImage?
    private var previewTimer: Timer?
    private var previewSequence = 0

    init(model: AppModel, startAt step: Step) {
        self.model = model
        self.step = step
        self.startStep = step
        refreshCameraStatus()
        if step == .enroll || step == .test { startPreview() }
    }

    var title: String {
        switch step {
        case .welcome: return "Welcome to FaceUnlock"
        case .camera: return "Camera access"
        case .enroll: return "Enroll your face"
        case .test: return "Check that it recognizes you"
        case .features: return "Turn on what you want"
        case .done: return "You're set"
        }
    }

    // MARK: - Camera

    func refreshCameraStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthorized = status == .authorized
        cameraDenied = status == .denied || status == .restricted
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { [self] in
                refreshCameraStatus()
                if granted { advance() }
            }
        }
    }

    // MARK: - Preview

    func startPreview() {
        guard previewTimer == nil, let runtime = model.runtime else { return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let frame = runtime.camera.frame(newerThan: self.previewSequence) else { return }
                self.previewSequence = frame.sequence
                self.preview = frame.image
            }
        }
    }

    func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        preview = nil
    }

    // MARK: - Enrollment

    func startEnrollment() {
        guard !enrolling, let runtime = model.runtime else { return }
        enrolling = true
        enrollFinished = false
        samplesCaptured = 0
        enrollHint = "Hold still and look straight at the camera."
        enrollHintTone = .neutral
        startPreview()
        let enroller = runtime.enroller()
        sampleTarget = enroller.target
        DispatchQueue.global(qos: .userInitiated).async {
            enroller.run { progress in
                DispatchQueue.main.async { [self] in apply(progress) }
            }
            DispatchQueue.main.async { [self] in enrolling = false }
        }
    }

    private func apply(_ progress: EnrollmentProgress) {
        switch progress {
        case .sampleCaptured(let count, let target, _):
            samplesCaptured = count
            sampleTarget = target
            enrollHint = "Keep looking at the camera…"
            enrollHintTone = .neutral
        case .rejectedNotLive:
            enrollHint = "Make sure it's your real face, well lit — photos and screens are rejected."
            enrollHintTone = .warn
        case .finished(let minAgreement, _):
            enrollFinished = true
            enrollHint = String(format: "Saved. Sample agreement: %.2f", minAgreement)
            enrollHintTone = .good
            model.log.write(String(format: "enrolled with minimum sample agreement %.3f", minAgreement))
            // Hold the success state so the checkmark is seen; Back/close/Continue cancel it.
            advanceTask?.cancel()
            advanceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self, self.step == .enroll else { return }
                self.advance()
            }
        case .failed(let message):
            enrollHint = message
            enrollHintTone = .warn
        }
    }

    // MARK: - Test

    func runTest() {
        guard !testing, let runtime = model.runtime else { return }
        testing = true
        testMessage = nil
        startPreview()
        let verifier = runtime.verifier(interactive: true, strictness: model.strictness)
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = verifier.run(timeout: 8, requiredConsecutive: 2, waitForTurn: 1, keepGoing: { true })
            DispatchQueue.main.async { [self] in
                testing = false
                testPassed = outcome.matched
                if outcome.matched {
                    testMessage = String(format: "Recognized you (match %.2f, liveness %.2f).", outcome.bestSimilarity, outcome.bestLiveness)
                } else if let failure = outcome.failure {
                    testMessage = failure
                } else if outcome.framesEvaluated == 0 {
                    testMessage = "No face was visible. Sit in front of the camera and try again."
                } else {
                    testMessage = String(format: "Not recognized (best match %.2f, liveness %.2f). Try better lighting, or re-enroll.", outcome.bestSimilarity, outcome.bestLiveness)
                }
                model.log.write("setup test: \(outcome.summary)")
            }
        }
    }

    // MARK: - Password

    func saveLoginPassword() {
        guard !password.isEmpty else {
            passwordMessage = "Enter your login password."
            return
        }
        guard password == passwordConfirm else {
            passwordMessage = "The two passwords don't match."
            return
        }
        if let error = model.saveLoginPassword(password) {
            passwordMessage = error
            return
        }
        password = ""
        passwordConfirm = ""
        passwordMessage = "Password saved."
        model.setLockScreenEnabled(true)
    }

    // MARK: - Navigation

    var canGoBack: Bool { step.rawValue > startStep.rawValue && !enrolling }

    func back() {
        guard canGoBack, let prev = Step(rawValue: step.rawValue - 1) else { return }
        advanceTask?.cancel()
        step = prev
        if prev == .enroll || prev == .test { startPreview() } else { stopPreview() }
    }

    func advance() {
        advanceTask?.cancel()
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .enroll || next == .test { startPreview() } else { stopPreview() }
    }

    func finish() {
        advanceTask?.cancel()
        stopPreview()
        model.finishSetup()
    }

    func close() {
        advanceTask?.cancel()
        stopPreview()
        model.windows.close(id: "setup")
    }
}
