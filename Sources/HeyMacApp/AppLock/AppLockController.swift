import AppKit
import HeyMacEngine

/// Runs App Lock: watches for locked apps, and for each one runs a shield + auth episode.
/// One episode at a time; extra apps queue behind it.
@MainActor
final class AppLockController {
    static let shared = AppLockController()

    let store = LockedAppStore()
    /// Supplied by `AppModel`; nil when face unlock isn't set up, paused, or the models failed to load.
    var faceMatcher: () -> FaceMatching? = { nil }
    /// Set only by `AppDelegate` after a successful `authorize`, so `applicationShouldTerminate` lets that
    /// one quit through. Logout/shutdown/restart get the normal authenticated quit prompt.
    var quitAuthorized = false

    private let sessions = SessionBook()
    private let shield = ShieldController()
    private let watcher = AppWatcher()
    private let system = LocalSystemAuth()
    private var episode: Task<Void, Never>?
    private var activeApp: NSRunningApplication?
    private var queue: [NSRunningApplication] = []
    private var justActivatedPID: pid_t?
    private var running = false
    private var systemTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    var protectsQuit: Bool { store.enabled && !store.apps.isEmpty }

    // MARK: - Lifecycle

    func start() {
        guard store.enabled, !running else { return }
        running = true
        shield.prepare()
        watcher.isLocked = { [store] in store.isLocked($0) }
        watcher.onCandidate = { [weak self] in self?.handleCandidate($0) }
        watcher.onActivate = { [weak self] app in
            if let id = app.bundleIdentifier { self?.sessions.focusGained(id) }
            self?.abandonEpisodeIfSwitchedAway(to: app)
        }
        watcher.onDeactivate = { [weak self] app in
            if let id = app.bundleIdentifier { self?.sessions.focusLost(id) }
        }
        watcher.onBackgroundLocked = { [weak self] app in
            guard let self, let id = app.bundleIdentifier, !self.sessions.isUnlocked(id), !app.isHidden else { return }
            // Never touch the episode's own apps (active or queued) or one that is still launching.
            let pid = app.processIdentifier
            if activeApp?.processIdentifier == pid || queue.contains(where: { $0.processIdentifier == pid }) { return }
            if let launched = app.launchDate, Date().timeIntervalSince(launched) < 5 { return }
            log("hiding \(id): background-locked")
            app.hide()
        }
        watcher.onTerminate = { [weak self] app in self?.handleTerminate(app) }
        watcher.start()
        observeSystemEvents()
    }

    func stop() {
        guard running else { return }
        running = false
        quitAuthorized = false
        watcher.stop()
        endEverything()
        sessions.revokeAll()
        let center = NSWorkspace.shared.notificationCenter
        systemTokens.forEach { center.removeObserver($0) }
        systemTokens.removeAll()
        distributedTokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedTokens.removeAll()
    }

    /// The same auth chain used for unlocking apps, for guarding quit and disabling protection.
    /// Quitting/disabling while a shield episode is active is denied; finish or "Quit App" first.
    func authorize(reason: String) async -> Bool {
        if activeApp != nil { return false }
        let outcome = await makeCoordinator().run(reason: reason)
        if case .unlocked = outcome { return true }
        return false
    }

    // MARK: - Episodes

    private func handleCandidate(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, !sessions.isUnlocked(id) else { return }
        if activeApp?.processIdentifier == app.processIdentifier { return }
        guard activeApp == nil else {
            if !queue.contains(where: { $0.processIdentifier == app.processIdentifier }) { queue.append(app) }
            return
        }
        begin(app)
    }

    private func log(_ message: String) { AppLog.shared.write("app lock: \(message)") }

    private func begin(_ app: NSRunningApplication) {
        log("begin \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier)")
        activeApp = app
        shield.model.onRetry = { [weak self] in self?.retry() }
        shield.model.onQuitApp = { [weak self] in self?.quitActiveApp() }
        shield.present(appName: app.localizedName ?? app.bundleIdentifier ?? "App", icon: app.icon,
                       pid: app.processIdentifier, mode: ShieldMode.saved)
        // Us, not the locked app, must be frontmost so keystrokes can't reach it.
        NSApp.activate(ignoringOtherApps: true)
        startAuthentication(for: app)
    }

    private func startAuthentication(for app: NSRunningApplication) {
        shield.model.phase = .scanning
        NotchOverlayController.shared.beginScanning(onLockScreen: false)
        episode = Task { [weak self] in
            guard let self else { return }
            let name = app.localizedName ?? "this app"
            let outcome = await makeCoordinator().run(reason: "Unlock \(name)")
            guard !Task.isCancelled, activeApp?.processIdentifier == app.processIdentifier else { return }
            await finish(app, outcome)
        }
    }

    private func finish(_ app: NSRunningApplication, _ outcome: AuthOutcome) async {
        let bid = app.bundleIdentifier ?? "?"
        switch outcome {
        case .unlocked:
            log("finish \(bid): unlocked")
            if let id = app.bundleIdentifier {
                sessions.unlock(id, policy: store.app(id)?.policy ?? .afterMinutes(5))
            }
            NotchOverlayController.shared.finish(success: true)
            shield.model.phase = .unlocked
            try? await Task.sleep(for: .milliseconds(450)) // let the unlock clip start
            guard activeApp?.processIdentifier == app.processIdentifier else { return }
            log("shield dismissed: unlocked")
            shield.dismiss()
            app.unhide()
            justActivatedPID = app.processIdentifier
            app.activate()
            endEpisode()
        case .cancelled:
            log("finish \(bid): cancelled")
            NotchOverlayController.shared.finish(success: false)
            shield.model.phase = .needsAuth("Authentication was cancelled")
        case .denied(let message):
            log("finish \(bid): denied")
            NotchOverlayController.shared.finish(success: false)
            shield.model.phase = .needsAuth(message)
        }
    }

    private func retry() {
        guard let app = activeApp else { return }
        episode?.cancel()
        startAuthentication(for: app)
    }

    private func quitActiveApp() {
        episode?.cancel()
        log("hiding \(activeApp?.bundleIdentifier ?? "?"): quit-app")
        activeApp?.hide() // a save sheet or window must not show once the shield drops
        activeApp?.terminate()
        NotchOverlayController.shared.cancelScanning()
        log("shield dismissed: quit-app")
        shield.dismiss()
        endEpisode()
    }

    private func endEpisode() {
        episode = nil
        activeApp = nil
        if !queue.isEmpty { begin(queue.removeFirst()) }
    }

    private func endEverything() {
        let hadEpisode = activeApp != nil || episode != nil
        episode?.cancel()
        episode = nil
        activeApp = nil
        justActivatedPID = nil
        queue.removeAll()
        if hadEpisode { NotchOverlayController.shared.cancelScanning() } // the island may belong to a lock-screen scan
        log("shield dismissed: revoked/stopped")
        shield.dismiss()
    }

    /// The user Cmd-Tabbed to some other app mid-episode: drop the shield so they can use it.
    /// The locked app stays locked (no session) and is hidden; coming back starts a new episode.
    /// Only regular apps count — the system's Touch ID sheet must not abandon the episode.
    /// The late `didActivate` of the app `finish` just unlocked and activated is skipped once
    /// (`justActivatedPID`), so it can't kill the next queued episode.
    private func abandonEpisodeIfSwitchedAway(to app: NSRunningApplication) {
        if app.processIdentifier == justActivatedPID { justActivatedPID = nil; return }
        guard let locked = activeApp, app.activationPolicy == .regular,
              app.processIdentifier != locked.processIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let lockedPID = locked.processIdentifier
        let otherPID = app.processIdentifier
        let lockedID = locked.bundleIdentifier ?? "?"
        let otherID = app.bundleIdentifier ?? "?"
        log("abandon scheduled: \(lockedID) because \(otherID) activated")
        // Debounce: a transient activation (launch/hide transitions) must not drop the shield.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let current = self.activeApp, current.processIdentifier == lockedPID,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == otherPID else {
                    self.log("abandon cancelled: \(lockedID) (transient activation of \(otherID))")
                    return
                }
                self.episode?.cancel()
                NotchOverlayController.shared.cancelScanning()
                self.log("shield dismissed: switched-away to \(otherID)")
                self.shield.dismiss()
                self.log("hiding \(lockedID): switched-away")
                current.hide()
                self.endEpisode()
            }
        }
    }

    private func handleTerminate(_ app: NSRunningApplication) {
        if let id = app.bundleIdentifier { sessions.revoke(id) }
        log("terminate seen: \(app.bundleIdentifier ?? "?")")
        queue.removeAll { $0.processIdentifier == app.processIdentifier }
        if activeApp?.processIdentifier == app.processIdentifier {
            episode?.cancel()
            NotchOverlayController.shared.cancelScanning()
            log("shield dismissed: app-terminated")
            shield.dismiss()
            endEpisode()
        }
    }

    private func makeCoordinator() -> AuthCoordinator {
        let face = faceMatcher().map { FaceVerifierAuthSource(matcher: $0) }
        return AuthCoordinator(face: face, system: system, faceTimeout: 3)
    }

    // MARK: - Revocation

    /// Sleep, screen lock and fast user switching drop every session and any open episode;
    /// the frontmost locked app is picked up again by the watcher's reconcile on wake.
    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in names {
            systemTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.revokeAll() }
            })
        }
        distributedTokens.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revokeAll() }
        })
    }

    private func revokeAll() {
        sessions.revokeAll()
        if let a = activeApp { log("hiding \(a.bundleIdentifier ?? "?"): revoke") }
        activeApp?.hide()
        endEverything()
    }
}
