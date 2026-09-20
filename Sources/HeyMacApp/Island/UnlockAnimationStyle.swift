import Foundation

/// How the island presents an unlock. A UI-only preference, so it lives in UserDefaults
/// here rather than in the engine's settings.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    /// Widens a little: lock glyph on one side, a small clip on the other.
    case minimal
    /// Grows into a large panel that plays the full animation.
    case original

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    private static let defaultsKey = "unlockAnimationStyle"

    static var saved: UnlockAnimationStyle {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .minimal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
