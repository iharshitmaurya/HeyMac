import AppKit
import ApplicationServices
import AVFoundation
import Observation
import ServiceManagement
import SwiftUI
import FaceUnlockCore
import FaceUnlockEngine

/// The app's single source of truth: mirrors settings for the UI, owns the engine, and
/// performs the actions the menu and windows trigger.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = EngineSettings()
    let log = AppLog.shared
    let windows = WindowPresenter()
    let pam: PamInstaller
    private(set) var runtime: FaceUnlockRuntime?
    private var controller: EngineController?

    private(set) var setupComplete = false
    private(set) var sudoEnabled = false
    private(set) var lockScreenEnabled = false
    private(set) var paused = false
    private(set) var lockScreenNeedsPassword = false
    private(set) var strictness: MatchStrictness = .normal
    private(set) var launchAtLogin = true
    private(set) var animationStyle = UnlockAnimationStyle.saved
    private(set) var appLockEnabled = false
    private(set) var appLockApps: [LockedApp] = []
    private(set) var pamStatus: PamStatus = .notInstalled
    private(set) var accessibilityTrusted = false
    private(set) var cameraAuthorized = false
    private(set) var busy = false
    private(set) var lastEvent = "no checks yet"
    private(set) var startupError: String?
    private(set) var unlocksToday = 0
    private var unlocksTodayKey = "" // yyyy-MM-dd; a new day resets the count
    var actionError: String?

    private init() {
        let resources = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("pam")
        pam = PamInstaller(resourcesDirectory: resources)

        if LegacyAgentMigration.migrateIfNeeded() {
            log.write("removed the old faceunlockd LaunchAgent (the app replaces it)")
        }
        do {
            runtime = try FaceUnlockRuntime()
        } catch {
            startupError = "Face models failed to load: \(error)"
            log.write(startupError ?? "")
        }

        reloadSettings()
        refreshSystemState()
        applyLaunchAtLogin()
        restartEngine()
        AppLockController.shared.faceMatcher = { [weak self] in
            guard let self, self.setupComplete, !self.paused, let runtime = self.runtime else { return nil }
            return runtime.verifier(interactive: false, strictness: self.strictness)
        }
        DispatchQueue.main.async { AppLockController.shared.start() }
        if AppLockController.shared.store.enabled { AppLockAgent.register() }

        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshSystemState() }
        }
        if !setupComplete {
            DispatchQueue.main.async { [self] in openSetup() }
        }
    }

    // MARK: - Derived state

    var problems: [String] {
        var found: [String] = []
        if setupComplete {
            if !cameraAuthorized { found.append("Camera access is off") }
            if sudoEnabled && pamStatus != .installed { found.append("sudo support needs reinstalling") }
            if lockScreenEnabled && !accessibilityTrusted { found.append("Accessibility permission is needed to type at the lock screen") }
            if lockScreenNeedsPassword { found.append("The stored password was rejected — save it again in Settings") }
        }
        if let actionError { found.append(actionError) }
        return found
    }

    var menuIconName: String {
        if startupError != nil || !problems.isEmpty { return "exclamationmark.triangle" }
        if !setupComplete { return "person.crop.circle.badge.questionmark" }
        if paused { return "pause.circle" }
        return "faceid"
    }

    // MARK: - Settings and system state

    func reloadSettings() {
        setupComplete = settings.setupComplete
        sudoEnabled = settings.sudoEnabled
        lockScreenEnabled = settings.lockScreenEnabled
        paused = settings.paused
        lockScreenNeedsPassword = settings.lockScreenNeedsPassword
        strictness = settings.strictness
        launchAtLogin = settings.launchAtLogin
        appLockEnabled = AppLockController.shared.store.enabled
        appLockApps = AppLockController.shared.store.apps
    }

    func refreshSystemState() {
        accessibilityTrusted = AXIsProcessTrusted()
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        pamStatus = pam.status()
        lockScreenNeedsPassword = settings.lockScreenNeedsPassword
    }

    // MARK: - Engine

    func restartEngine() {
        controller?.stop()
        controller = nil
        guard let runtime, settings.setupComplete else { return }
        let controller = EngineController(runtime: runtime, settings: settings, log: log) { event in
            Task { @MainActor in AppModel.shared.handle(event) }
        }
        do {
            try controller.start()
            self.controller = controller
        } catch {
            actionError = "Could not start face unlock: \(error)"
            log.write(actionError ?? "")
        }
    }

    func stopEngine() {
        controller?.stop()
        controller = nil
    }

    func handle(_ event: EngineEvent) {
        let time = Date().formatted(date: .omitted, time: .shortened)
        switch event {
        case .sudo(let matched, _):
            lastEvent = matched ? "sudo unlocked \(time)" : "sudo not recognized \(time)"
            if matched { countUnlock() }
        case .lockScreenScanning:
            lastEvent = "lock screen scanning \(time)"
        case .lockScreenUnlocked:
            lastEvent = "lock screen unlocked \(time)"
            countUnlock()
        case .lockScreenPasswordRejected:
            lastEvent = "stored password rejected \(time)"
            lockScreenNeedsPassword = true
        case .lockScreenProblem(let reason):
            lastEvent = reason
        }
        NotchOverlayController.shared.handle(event)
    }

    private func countUnlock() {
        let today = Date().formatted(.iso8601.year().month().day())
        if unlocksTodayKey != today {
            unlocksTodayKey = today
            unlocksToday = 0
        }
        unlocksToday += 1
    }

    // MARK: - Actions

    func setSudoEnabled(_ enabled: Bool) {
        guard !busy else { return }
        busy = true
        actionError = nil
        let installer = pam
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { enabled ? try installer.install() : try installer.uninstall() }
            DispatchQueue.main.async { [self] in finishSudoChange(enabled: enabled, result: result) }
        }
    }

    private func finishSudoChange(enabled: Bool, result: Result<Void, Error>) {
        busy = false
        switch result {
        case .success:
            settings.sudoEnabled = enabled
            log.write("sudo face unlock \(enabled ? "installed" : "removed")")
        case .failure(PamInstallerError.cancelled):
            break
        case .failure(let error):
            actionError = "Could not \(enabled ? "turn on" : "turn off") sudo unlock: \(error)"
            log.write(actionError ?? "")
        }
        reloadSettings()
        refreshSystemState()
    }

    func setLockScreenEnabled(_ enabled: Bool) {
        if enabled, !(runtime?.hasLoginPassword ?? false) {
            actionError = "Save your login password in Settings before turning this on"
            openSettings()
            return
        }
        actionError = nil
        settings.lockScreenEnabled = enabled
        reloadSettings()
        log.write("lock-screen face unlock \(enabled ? "on" : "off")")
        if enabled && !accessibilityTrusted { requestAccessibility() }
    }

    func setPaused(_ paused: Bool) {
        settings.paused = paused
        reloadSettings()
        log.write(paused ? "paused" : "resumed")
    }

    /// Saves the choice and plays it on the desktop so it can be judged without locking the screen.
    func setAnimationStyle(_ style: UnlockAnimationStyle) {
        UnlockAnimationStyle.saved = style
        animationStyle = style
        NotchOverlayController.shared.preview(style)
    }

    func setStrictness(_ value: MatchStrictness) {
        settings.strictness = value
        reloadSettings()
        restartEngine()
    }

    // MARK: - App Lock

    func addLockedApp(_ app: InstalledApp) {
        AppLockController.shared.store.add(bundleID: app.bundleID, name: app.name)
        reloadSettings()
    }

    func removeLockedApp(_ bundleID: String) {
        let controller = AppLockController.shared
        guard controller.store.enabled else {
            controller.store.remove(bundleID: bundleID)
            reloadSettings()
            return
        }
        Task { @MainActor in
            guard await controller.authorize(reason: "Stop locking this app") else { reloadSettings(); return }
            controller.store.remove(bundleID: bundleID)
            reloadSettings()
        }
    }

    func setLockedAppPolicy(_ policy: RelockPolicy, for bundleID: String) {
        AppLockController.shared.store.setPolicy(policy, for: bundleID)
        reloadSettings()
    }

    /// Turning it on is immediate. Turning it off must authenticate first.
    func setAppLockEnabled(_ enabled: Bool) {
        let controller = AppLockController.shared
        if enabled {
            controller.store.enabled = true
            controller.start()
            AppLockAgent.register()
            reloadSettings()
            return
        }
        Task { @MainActor in
            guard await controller.authorize(reason: "Turn off App Lock") else { reloadSettings(); return }
            controller.store.enabled = false
            controller.stop()
            AppLockAgent.unregister()
            reloadSettings()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        reloadSettings()
        applyLaunchAtLogin()
    }

    private func applyLaunchAtLogin() {
        // Only once the user has finished setup: a half-configured or test build must not
        // register itself to start at login.
        guard settings.setupComplete else { return }
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.write("could not change the launch-at-login setting: \(error)")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityTrusted { openSystemSettings(anchor: "Privacy_Accessibility") }
    }

    func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    func saveLoginPassword(_ password: String) -> String? {
        guard let runtime else { return "Face models are not loaded" }
        do {
            try runtime.saveLoginPassword(password)
            settings.lockScreenNeedsPassword = false
            reloadSettings()
            log.write("stored login password updated")
            return nil
        } catch {
            return "Could not save the password: \(error)"
        }
    }

    func removeAllData() {
        stopEngine()
        if pamStatus != .notInstalled { try? pam.uninstall() }
        do {
            try runtime?.removeAllData()
        } catch {
            actionError = "Could not remove everything: \(error)"
        }
        settings.resetAll()
        reloadSettings()
        refreshSystemState()
        log.write("removed face data and settings")
        openSetup()
    }

    func finishSetup() {
        settings.setupComplete = true
        reloadSettings()
        applyLaunchAtLogin()
        restartEngine()
        windows.close(id: "setup")
    }

    // MARK: - Windows

    func openSetup() {
        let flow = SetupFlow(model: self, startAt: .welcome)
        windows.show(id: "setup", title: "Set Up FaceUnlock", size: CGSize(width: 520, height: 560)) {
            SetupWizardView(flow: flow)
        }
    }

    func openTest() {
        let flow = SetupFlow(model: self, startAt: .test)
        windows.show(id: "setup", title: "Test FaceUnlock", size: CGSize(width: 520, height: 560)) {
            SetupWizardView(flow: flow)
        }
    }

    func reEnroll() {
        // Verification must not run against a half-written enrollment, and the camera can
        // only serve one user at a time.
        settings.setupComplete = false
        reloadSettings()
        stopEngine()
        let flow = SetupFlow(model: self, startAt: .enroll)
        windows.show(id: "setup", title: "Re-enroll Your Face", size: CGSize(width: 520, height: 560)) {
            SetupWizardView(flow: flow)
        }
    }

    func openSettings() {
        windows.show(id: "settings", title: "FaceUnlock Settings", size: CGSize(width: 560, height: 460)) {
            SettingsView(model: self)
        }
    }
}
