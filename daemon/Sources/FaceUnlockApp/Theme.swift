import SwiftUI

/// Color tokens shared by the menu, settings and wizard — one accent and semantic
/// status colors. Matches the "FaceUnlock, redrawn" interface concept: a single soft blue
/// accent, flat fills, no gradients or glow shadows.
enum Theme {
    static let accent = Color(hex: 0x6C93E8)
    static let accentInk = Color(hex: 0x0D1A33)
    static let good = Color(hex: 0x59C77E)
    static let warn = Color(hex: 0xE3A93C)
    static let bad = Color(hex: 0xEF6F5E)

    // TEXT / hairline variants: AA-passing in both appearances. Use these when the color is a
    // foreground; keep the bright values above for fills and dots.
    // Contrast (WCAG 2.1) light value on white / on light card (#E4E4E4); dark value on #2A2A2A:
    //   accentText 6.55 / 5.15 ; 4.77      goodText 6.15 / 4.83 ; 6.76
    //   warnText   7.06 / 5.55 ; 6.84      badText  6.37 / 5.01 ; 4.86
    static let accentText = Color(light: 0x3559B0, dark: 0x6C93E8)
    static let goodText = Color(light: 0x17703B, dark: 0x59C77E)
    static let warnText = Color(light: 0x7A5000, dark: 0xE3A93C)
    static let badText = Color(light: 0xB03024, dark: 0xEF6F5E)
}

/// 8-pt spacing scale.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6      // icon tile
    static let md: CGFloat = 10     // sidebar item, small tile
    static let lg: CGFloat = 14     // card
    static let style: RoundedCornerStyle = .continuous
}

enum IconSize {
    static let dot: CGFloat = 6
    static let glyph: CGFloat = 12
    static let tile: CGFloat = 22
    static let app: CGFloat = 26
    static let avatar: CGFloat = 40
}

/// Mirrors what the views use today (13 semibold rows, 11.5 secondary captions, 15.5 bold titles).
enum Typography {
    static let pageTitle = Font.system(size: 15.5, weight: .bold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11.5, weight: .regular)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
}

enum Surface {
    static let card = Color.primary.opacity(0.05)
    static let hairline = Color.primary.opacity(0.12)
    /// Divider leading inset == row label inset.
    static let rowInset: CGFloat = Spacing.lg
}

extension Color {
    /// Two literals resolved per appearance.
    init(light: UInt32, dark: UInt32) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A flat accent-filled pill button — no gradient, no glow. Pressed and disabled states.
/// ponytail: no hover — it needs per-view state (@State is unavailable here); add when the toolchain allows.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(background)
                .foregroundStyle(foreground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(stroke, lineWidth: 1)
                )
                .opacity(isEnabled ? (pressed ? 0.85 : 1) : 0.45)
        }

        private var stroke: Color {
            switch kind {
            case .primary: return .clear
            case .secondary: return Surface.hairline
            case .danger: return Theme.bad.opacity(0.35)
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return Theme.accent
            case .secondary: return Color.primary.opacity(0.06)
            case .danger: return Color.clear
            }
        }

        private var foreground: Color {
            switch kind {
            case .primary: return Theme.accentInk
            case .secondary: return .primary
            case .danger: return Theme.badText
            }
        }
    }
}

/// A small status chip — colored dot plus label, used for "Installed", "Needs setup", etc.
struct StatusChip: View {
    enum Tone { case good, warn, bad, idle
        var color: Color {
            switch self {
            case .good: return Theme.good
            case .warn: return Theme.warn
            case .bad: return Theme.bad
            case .idle: return .secondary
            }
        }
        /// Adaptive AA text variant of `color`.
        var textColor: Color {
            switch self {
            case .good: return Theme.goodText
            case .warn: return Theme.warnText
            case .bad: return Theme.badText
            case .idle: return .secondary
            }
        }
    }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.16))
        .clipShape(Capsule())
    }
}
