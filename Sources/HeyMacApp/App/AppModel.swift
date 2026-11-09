import AppKit
import ApplicationServices
import AVFoundation
import Observation
import ServiceManagement
import SwiftUI
import HeyMacCore
import HeyMacEngine

/// The app's single source of truth: mirrors settings for the UI, owns the engine, and
/// performs the actions the menu and windows trigger.
@MainActor
@Observable
final class AppModel {
    /// Set by `--render-ui` before first access: the model then holds fixed sample state and has no side effects.
    nonisolated(unsafe) static var uiSnapshotMode = false
    static let shared = AppModel()

    let settings = EngineSettings()
    let log = AppLog.shared
    let windows = WindowPresenter()
    private(set) var runtime: HeyMacRuntime?
    private var controller: EngineController?

    private(set) var setupComplete = false
    private(set) var lockScreenEnabled = false
    private(set) var paused = false
    private(set) var lockScreenNeedsPassword = false
    private(set) var strictness: MatchStrictness = .normal
    private(set) var launchAtLogin = true
    private(set) var animationStyle = UnlockAnimationStyle.saved
    private(set) var animationEnabled = UnlockAnimationStyle.enabled
    private(set) var appLockEnabled = false
    private(set) var appLockApps: [LockedApp] = []
    private(set) var shieldMode = ShieldMode.saved
    private(set) var accessibilityTrusted = false
    private(set) var cameraAuthorized = false
    private(set) var busy = false
    private(set) var lastEvent = L10n.text("No checks yet")
    private(set) var startupError: String?
    private(set) var engineError: String?
    private(set) var unlocksToday = 0
    private var activityStore = LockScreenActivityStore()
    var actionError: String?
    private(set) var snapshotPasswordSaved = true

    private init() {
        if Self.uiSnapshotMode {
            // Deterministic sample state for the QA renderer; no runtime, engine, agent, timer or window.
            let sample = #"[{"bundleID":"net.whatsapp.WhatsApp","name":"\u200EWhatsApp","policy":{"everyTime":{}}},{"bundleID":"com.brave.Browser","name":"Brave Browser","policy":{"afterMinutes":{"_0":5}}},{"bundleID":"com.microsoft.Powerpoint","name":"Microsoft PowerPoint Insider Preview Edition","policy":{"afterFocusLossMinutes":{"_0":5}}},{"bundleID":"com.apple.Notes","name":"Notes","policy":{"afterMinutes":{"_0":15}}}]"#
            appLockApps = (try? JSONDecoder().decode([LockedApp].self, from: Data(sample.utf8))) ?? []
            setupComplete = true; lockScreenEnabled = true; paused = false
            strictness = .normal; unlocksToday = 42; launchAtLogin = true
            accessibilityTrusted = true; cameraAuthorized = true; appLockEnabled = true
            animationStyle = .minimal
            shieldMode = .fullScreen
            lastEvent = L10n.format("Lock Screen unlocked at %@", "9:41 AM")
            return
        }

        do {
            runtime = try HeyMacRuntime()
        } catch {
            startupError = L10n.format("Face models failed to load: %@", String(describing: error))
            log.write(startupError ?? "")
        }

        restoreActivity()
        reloadSettings()
        refreshSystemState()
        applyLaunchAtLogin()
        restartEngine()
        AppLockController.shared.faceMatcher = { [weak self] in
            guard let self, self.setupComplete, !self.paused, !self.busy, let runtime = self.runtime else { return nil }
            return runtime.verifier(interactive: false, strictness: self.strictness)
        }
        DispatchQueue.main.async { AppLockController.shared.start() }
        if AppLockController.shared.store.enabled { AppLockAgent.register() }

        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in AppModel.shared.refreshSystemState() }
        }
        if !settings.onboardingComplete {
            DispatchQueue.main.async { [self] in openSetup() }
        }
    }

    /// Sample scenarios are only available in the isolated render process; never touch saved settings.
    func configureSnapshot(_ scenario: String, apps: [LockedApp]) {
        precondition(Self.uiSnapshotMode)
        setupComplete = true; lockScreenEnabled = true; appLockEnabled = true
        paused = false; busy = false; cameraAuthorized = true; accessibilityTrusted = true
        lockScreenNeedsPassword = false; snapshotPasswordSaved = true
        startupError = nil; engineError = nil; actionError = nil; appLockApps = apps
        for token in scenario.split(separator: "+").map(String.init) {
        switch token {
        case "lock-off": lockScreenEnabled = false
        case "apps-off": appLockEnabled = false
        case "face-setup": busy = true
        case "off": lockScreenEnabled = false; appLockEnabled = false
        case "paused": paused = true
        case "camera-denied": cameraAuthorized = false
        case "accessibility-denied": accessibilityTrusted = false
        case "no-face": setupComplete = false
        case "empty-apps": appLockApps = []
        case "password-rejected": lockScreenNeedsPassword = true
        case "password-missing": snapshotPasswordSaved = false
        case "engine-error": engineError = "Could not start face unlock. Review face setup."
        case "apps-only": lockScreenEnabled = false; setupComplete = false
        default: break
        }
        }
        if scenario == "off" { precondition(lockStatus.label == "Off" && protectionStatus.label == "Off") }
        if scenario == "paused" { precondition(lockStatus.label == "Paused" && protectionStatus.action == .resume) }
        if scenario == "empty-apps" { precondition(protectionStatus.tone == .warn && protectionStatus.action == .addApp) }
        if ["camera-denied", "no-face", "password-rejected", "password-missing", "apps-only", "engine-error"].contains(scenario) { precondition(protectionStatus.tone == .warn) }
    }

    // MARK: - Derived state

    var problems: [String] {
        var found: [String] = []
        if setupComplete {
            if !cameraAuthorized { found.append("Camera access is off") }
            if lockScreenEnabled && !accessibilityTrusted { found.append("Accessibility permission is needed to type at the lock screen") }
            if lockScreenNeedsPassword { found.append("The stored password was rejected — save it again in Settings") }
        }
        if let actionError { found.append(actionError) }
        return found
    }

    var menuIconName: String {
        if protectionStatus.tone == .warn { return "exclamationmark.triangle" }
        if paused { return "pause.circle" }
        if !lockScreenEnabled && !appLockEnabled { return "shield" }
        return "faceid"
    }

    // MARK: - Settings and system state

    func reloadSettings() {
        setupComplete = settings.setupComplete
        lockScreenEnabled = settings.lockScreenEnabled
        paused = settings.paused
        lockScreenNeedsPassword = settings.lockScreenNeedsPassword
        strictness = settings.strictness
        launchAtLogin = settings.launchAtLogin
        appLockEnabled = AppLockController.shared.store.enabled
        appLockApps = AppLockController.shared.store.apps
    }

    func refreshSystemState() {
        activityStore.refreshDay()
        unlocksToday = activityStore.unlocksToday
        accessibilityTrusted = AXIsProcessTrusted()
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        lockScreenNeedsPassword = settings.lockScreenNeedsPassword
    }

    // MARK: - Engine

    func restartEngine() {
        if actionError == engineError { actionError = nil }
        engineError = nil
        controller?.stop()
        controller = nil
        guard let runtime, settings.setupComplete, !busy else { return }
        let controller = EngineController(runtime: runtime, settings: settings, log: log) { event in
            Task { @MainActor in AppModel.shared.handle(event) }
        }
        do {
            try controller.start()
            self.controller = controller
        } catch {
            engineError = L10n.format("Could not start face unlock: %@", String(describing: error))
            actionError = engineError
            log.write(actionError ?? "")
        }
    }

    func stopEngine() {
        controller?.stop()
        controller = nil
    }

    func handle(_ event: EngineEvent) {
        switch event {
        case .lockScreenScanning:
            activityStore.recordEvent(.scanning)
            lastEvent = activityStore.lastEvent
        case .lockScreenUnlocked:
            activityStore.recordEvent(.unlocked)
            lastEvent = activityStore.lastEvent
            countUnlock()
        case .lockScreenPasswordRejected:
            activityStore.recordEvent(.passwordRejected)
            lastEvent = activityStore.lastEvent
            lockScreenNeedsPassword = true
        case .lockScreenNoMatch:
            activityStore.recordEvent(.noMatch)
            lastEvent = activityStore.lastEvent
        case .lockScreenNoFace:
            activityStore.recordEvent(.noFace)
            lastEvent = activityStore.lastEvent
        case .lockScreenScanEnded:
            activityStore.recordEvent(.scanEnded)
            lastEvent = activityStore.lastEvent
        case .lockScreenProblem(let reason):
            lastEvent = reason
            activityStore.recordEvent(lastEvent)
        }
        NotchOverlayController.shared.handle(event)
    }

    private func restoreActivity() {
        activityStore.restore()
        unlocksToday = activityStore.unlocksToday
        lastEvent = activityStore.lastEvent
    }

    private func countUnlock() {
        activityStore.recordUnlock()
        unlocksToday = activityStore.unlocksToday
    }

    // MARK: - Actions

    func setLockScreenEnabled(_ enabled: Bool) {
        if !enabled && lockScreenEnabled {
            Task { @MainActor in
                guard await authorizeChange(L10n.text("Turn off Lock Screen face unlock")) else { return }
                applyLockScreenEnabled(false)
            }
            return
        }
        applyLockScreenEnabled(enabled)
    }

    private func applyLockScreenEnabled(_ enabled: Bool) {
        if enabled, !(runtime?.hasLoginPassword ?? false) {
            actionError = "Add your login password in Settings › Lock Screen before turning this on."
            SettingsSelection.shared.pane = .lockScreen
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

    /// Turns the unlock animation on or off. Turning it on plays the current style once; turning it off
    /// stops a preview that is still playing.
    func setAnimationEnabled(_ enabled: Bool) {
        UnlockAnimationStyle.enabled = enabled
        animationEnabled = enabled
        if enabled {
            NotchOverlayController.shared.preview(animationStyle)
        } else {
            NotchOverlayController.shared.stopPreview()
        }
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

    func setShieldMode(_ mode: ShieldMode) {
        ShieldMode.saved = mode
        shieldMode = mode
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
        guard settings.onboardingComplete else { return }
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

    func authorizeChange(_ reason: String) async -> Bool {
        let result = await LocalSystemAuth().authenticate(reason: reason)
        guard !Task.isCancelled else { return false }
        switch result {
        case .success: actionError = nil; return true
        case .cancelled: return false
        case .failed(let message): actionError = message; return false
        }
    }

    func saveLoginPassword(_ password: String) async -> String? {
        guard await authorizeChange(L10n.text("Save your Mac login password in Hey Mac")) else { return L10n.text("Password unchanged. Authenticate to save it.") }
        guard let runtime else { return L10n.text("Face models are not loaded") }
        do {
            try runtime.saveLoginPassword(password)
            settings.lockScreenNeedsPassword = false
            reloadSettings()
            log.write("stored login password updated")
            return nil
        } catch {
            return L10n.format("Could not save the password: %@", String(describing: error))
        }
    }

    func removeAllData() {
        Task { @MainActor in
            guard await authorizeChange(L10n.text("Remove your face data")) else { return }
            stopEngine()
            do {
                guard let runtime else { throw SecureStoreError.notFound }
                try runtime.removeAllData()
                settings.setupComplete = false
                settings.lockScreenEnabled = false
                settings.lockScreenNeedsPassword = false
                reloadSettings()
                refreshSystemState()
                log.write("face data and saved login password removed; App Lock settings retained")
            } catch {
                actionError = L10n.format("Could not remove face data: %@", String(describing: error))
                restartEngine()
            }
        }
    }

    func beginFaceSetup() { busy = true; stopEngine() }
    func endFaceSetup() { busy = false; restartEngine() }
    func acceptFaceSetup() {
        settings.setupComplete = true
        reloadSettings()
    }

    /// Removes everything Hey Mac put on this Mac (face data, password, Keychain key, settings, log, login
    /// item and relaunch agent), moves the app to the Trash and quits. Asks App Lock to authorize first, so
    /// this can't be used to get around it. Returns without doing anything if that is refused.
    func uninstall() async {
        let lock = AppLockController.shared
        if lock.protectsQuit {
            guard await lock.authorize(reason: "Uninstall Hey Mac") else { return }
        }

        windows.close(id: "settings")
        lock.store.enabled = false
        lock.stop()
        stopEngine()
        AppLockAgent.unregister()
        if SMAppService.mainApp.status == .enabled { try? await SMAppService.mainApp.unregister() }

        try? runtime?.removeAllData()
        try? FileManager.default.removeItem(at: HeyMacRuntime.defaultSupportDirectory)
        try? FileManager.default.removeItem(at: AppLog.shared.url)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        }

        // Only a real .app (never the bare debug binary's build folder).
        let bundle = Bundle.main.bundleURL
        let trashed = bundle.pathExtension == "app" && (try? FileManager.default.trashItem(at: bundle, resultingItemURL: nil)) != nil
        if !trashed && bundle.pathExtension == "app" {
            let alert = NSAlert()
            alert.messageText = L10n.text("Hey Mac's data is removed")
            alert.informativeText = L10n.text("It couldn't move itself to the Trash. Drag Hey Mac from Applications to the Trash to finish.")
            alert.runModal()
        }
        exit(0) // no orderly quit: nothing may write settings back after they were deleted
    }

    func finishSetup() {
        settings.onboardingComplete = true
        reloadSettings()
        applyLaunchAtLogin()
        restartEngine()
        windows.close(id: "setup")
    }

    // MARK: - Windows

    func openSetup() {
        let flow = SetupFlow(model: self, startAt: .welcome)
        windows.show(id: "setup", title: "Set Up Hey Mac", size: CGSize(width: 720, height: 540), resizable: true, minSize: CGSize(width: 640, height: 500),
                     replacing: true, onClose: { flow.teardown() }) {
            SetupWizardView(flow: flow)
        }
    }

    func openTest() {
        let flow = SetupFlow(model: self, startAt: .test)
        windows.show(id: "setup", title: "Test Hey Mac", size: CGSize(width: 720, height: 540), resizable: true, minSize: CGSize(width: 640, height: 500),
                     replacing: true, onClose: { flow.teardown() }) {
            SetupWizardView(flow: flow)
        }
    }

    func reEnroll() {
        Task { @MainActor in
            guard await authorizeChange(L10n.text("Replace your face data")) else { return }
            beginFaceSetup()
            let flow = SetupFlow(model: self, startAt: .enroll)
            windows.show(id: "setup", title: "Set Up Your Face Again", size: CGSize(width: 720, height: 620), resizable: true, minSize: CGSize(width: 640, height: 500),
                         replacing: true, onClose: { flow.teardown() }) {
                SetupWizardView(flow: flow)
            }
        }
    }

    func openSettings() {
        windows.show(id: "settings", title: "Hey Mac Settings", size: CGSize(width: 900, height: 640),
                     resizable: true, minSize: CGSize(width: 640, height: 480), autosaveName: "HeyMacSettings") {
            SettingsView(model: self)
        }
    }
}
