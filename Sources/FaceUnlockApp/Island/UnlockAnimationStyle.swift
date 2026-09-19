import Foundation

/// How the notch island looks while it resolves an unlock. App-only preference, so it
/// lives in UserDefaults here rather than in the engine's settings.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    /// The island widens only a little: lock glyph on one side, small clip on the other.
    case minimal
    /// The island grows into a large panel showing the full animation.
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Minimal"
        case .original: return "Original"
        }
    }

    private static let key = "unlockAnimationStyle"

    static var saved: UnlockAnimationStyle {
        get { UnlockAnimationStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .minimal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
