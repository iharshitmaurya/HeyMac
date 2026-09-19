import FaceUnlockEngine
import ServiceManagement

/// A per-user launch agent with KeepAlive, so a crash or `kill` restarts FaceUnlock (and
/// every locked app relocks, since sessions live in memory). An authorized quit exits with
/// status 0, which the plist's `SuccessfulExit = false` treats as "don't restart".
enum AppLockAgent {
    private static var service: SMAppService { .agent(plistName: "com.faceunlock.app.agent.plist") }

    static func register() {
        guard service.status != .enabled else { return }
        do { try service.register() } catch { AppLog.shared.write("App Lock agent register failed: \(error)") }
    }

    static func unregister() {
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        do { try service.unregister() } catch { AppLog.shared.write("App Lock agent unregister failed: \(error)") }
    }
}
