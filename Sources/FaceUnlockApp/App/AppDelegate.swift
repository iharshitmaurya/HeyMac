import AppKit

/// Quit guard: while App Lock protects anything, quitting Hey Mac (menu, ⌘Q, or a
/// programmatic terminate) must first pass the same face → Touch ID → password chain.
/// Logout and shutdown go through the same prompt (`quitAuthorized` is set only after a successful authorize).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quitPromptActive = false

    func applicationWillTerminate(_ notification: Notification) {
        // App Lock was turned off: drop the relaunch agent now that we're exiting anyway.
        if !AppLockController.shared.store.enabled { AppLockAgent.unregister() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let controller = AppLockController.shared
        guard controller.protectsQuit, !controller.quitAuthorized else { return .terminateNow }
        guard !quitPromptActive else { return .terminateCancel } // one auth chain at a time
        quitPromptActive = true
        Task { @MainActor in
            let allowed = await controller.authorize(reason: "Quit Hey Mac")
            quitPromptActive = false
            if allowed { controller.quitAuthorized = true }
            sender.reply(toApplicationShouldTerminate: allowed)
            DispatchQueue.main.async { controller.quitAuthorized = false } // still alive => it was vetoed
        }
        return .terminateLater
    }
}
