import Foundation

/// How the App Lock shield covers the screen. Whole-screen is the default and the strongest;
/// app-windows-only blurs just the locked app (iOS-like) and can lag behind a moving window.
enum ShieldMode: String, CaseIterable, Identifiable {
    case fullScreen
    case appWindowsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullScreen: return "Whole screen"
        case .appWindowsOnly: return "Only the locked app"
        }
    }

    private static let key = "appLock.shieldMode"

    static var saved: ShieldMode {
        get { ShieldMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .fullScreen }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
