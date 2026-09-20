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
    private static let enabledKey = "unlockAnimationEnabled"

    /// Whether the island shows at all when the Mac is unlocked with a face. On unless turned off.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var saved: UnlockAnimationStyle {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .minimal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}
