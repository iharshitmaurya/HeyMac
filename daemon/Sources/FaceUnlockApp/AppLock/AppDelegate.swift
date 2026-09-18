import AppKit

/// Quit guard: while App Lock protects anything, quitting FaceUnlock (menu, ⌘Q, or a
/// programmatic terminate) must first pass the same face → Touch ID → password chain.
/// Logout and shutdown are let through (`quitAuthorized` is set by the controller).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let controller = AppLockController.shared
        guard controller.protectsQuit, !controller.quitAuthorized else { return .terminateNow }
        Task { @MainActor in
            let allowed = await controller.authorize(reason: "Quit FaceUnlock")
            if allowed { controller.quitAuthorized = true }
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
}
