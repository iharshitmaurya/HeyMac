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
    private(set) var lastEvent = "no checks yet"
    private(set) var startupError: String?
    private(set) var unlocksToday = 0
    private var unlocksTodayKey = "" // yyyy-MM-dd; a new day resets the count
    var actionError: String?

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
            lastEvent = "lock screen unlocked 9:41 AM"
            return
        }

        do {
            runtime = try HeyMacRuntime()
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
        if AppLockController.shared.store.enabled && setupComplete { AppLockAgent.register() }

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
        case .lockScreenScanning:
            lastEvent = "lock screen scanning \(time)"
        case .lockScreenUnlocked:
            lastEvent = "lock screen unlocked \(time)"
            countUnlock()
        case .lockScreenPasswordRejected:
            lastEvent = "stored password rejected \(time)"
            lockScreenNeedsPassword = true
        case .lockScreenScanEnded:
            lastEvent = "lock screen scan ended \(time)"
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

    func setLockScreenEnabled(_ enabled: Bool) {
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
            alert.messageText = "Hey Mac's data is removed"
            alert.informativeText = "It couldn't move itself to the Trash. Drag Hey Mac from Applications to the Trash to finish."
            alert.runModal()
        }
        exit(0) // no orderly quit: nothing may write settings back after they were deleted
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
        // Verification must not run against a half-written enrollment, and the camera can
        // only serve one user at a time.
        settings.setupComplete = false
        reloadSettings()
        stopEngine()
        let flow = SetupFlow(model: self, startAt: .enroll)
        windows.show(id: "setup", title: "Re-enroll Your Face", size: CGSize(width: 720, height: 540), resizable: true, minSize: CGSize(width: 640, height: 500),
                     replacing: true, onClose: { flow.teardown() }) {
            SetupWizardView(flow: flow)
        }
    }

    func openSettings() {
        windows.show(id: "settings", title: "Hey Mac Settings", size: CGSize(width: 720, height: 560),
                     resizable: true, minSize: CGSize(width: 640, height: 480), autosaveName: "HeyMacSettings") {
            SettingsView(model: self)
        }
    }
}
