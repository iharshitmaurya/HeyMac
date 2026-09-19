import AppKit

/// Detects locked apps appearing. Earliest signal first, all funneled into `onCandidate`:
/// a new process in `runningApplications`, activation, unhide, and a 2 s reconcile of the
/// frontmost app that catches any event we missed (and apps already running at startup).
@MainActor
final class AppWatcher {
    var isLocked: (String) -> Bool = { _ in false }
    var onCandidate: (NSRunningApplication) -> Void = { _ in }
    var onActivate: (NSRunningApplication) -> Void = { _ in }
    var onDeactivate: (NSRunningApplication) -> Void = { _ in }
    var onBackgroundLocked: (NSRunningApplication) -> Void = { _ in }
    var onTerminate: (NSRunningApplication) -> Void = { _ in }

    private var tokens: [NSObjectProtocol] = []
    private var runningObservation: NSKeyValueObservation?
    private var timer: Timer?

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (NSRunningApplication) -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { handler(app) }
            })
        }
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.onActivate(app)
            self?.consider(app)
        }
        observe(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in self?.consider(app) }
        observe(NSWorkspace.didDeactivateApplicationNotification) { [weak self] app in self?.onDeactivate(app) }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in self?.onTerminate(app) }

        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let known = Set((change.oldValue ?? []).map(\.processIdentifier))
            let added = (change.newValue ?? []).filter { !known.contains($0.processIdentifier) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { added.forEach { self?.consider($0) } }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        reconcile()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
        runningObservation = nil
        timer?.invalidate()
        timer = nil
    }

    private func reconcile() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front { consider(front) }
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, isLocked(id), app.activationPolicy == .regular, !app.isTerminated,
                  app.processIdentifier != front?.processIdentifier, app.processIdentifier != me else { continue }
            onBackgroundLocked(app)
        }
    }

    private func consider(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, isLocked(id),
              app.activationPolicy == .regular, !app.isTerminated else { return }
        onCandidate(app)
    }
}
