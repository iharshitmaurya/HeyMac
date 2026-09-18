import Foundation
import LocalAuthentication

/// Touch ID, then the macOS account password, both handled and verified by the system.
/// Nothing is stored here.
public final class LocalSystemAuth: SystemAuthSource, @unchecked Sendable {
    public init() {}

    public func authenticate(reason: String) async -> SystemAuthResult {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failed(error?.localizedDescription ?? "Authentication is unavailable")
        }
        return await withTaskCancellationHandler {
            do {
                let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                return ok ? .success : .failed("Not authenticated")
            } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
                return .cancelled
            } catch {
                return .failed(error.localizedDescription)
            }
        } onCancel: {
            context.invalidate()
        }
    }
}
