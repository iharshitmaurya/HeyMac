import Foundation

public enum WireMessage: Equatable {
    case verify
    case verifyLock
    case ok
    case fail

    public func encoded() -> Data {
        let string: String
        switch self {
        case .verify: string = "VERIFY\n"
        case .verifyLock: string = "VERIFY_LOCK\n"
        case .ok: string = "OK\n"
        case .fail: string = "FAIL\n"
        }
        return Data(string.utf8)
    }

    public static func decode(_ data: Data) -> WireMessage? {
        guard let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        switch string {
        case "VERIFY": return .verify
        case "VERIFY_LOCK": return .verifyLock
        case "OK": return .ok
        case "FAIL": return .fail
        default: return nil
        }
    }
}
