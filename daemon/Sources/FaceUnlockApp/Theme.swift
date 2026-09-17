import SwiftUI

/// Color and shape tokens shared by the menu, settings and wizard — one accent, semantic
/// status colors, and the radii used everywhere a panel or control is drawn. Matches the
/// "FaceUnlock, redrawn" interface concept: a single soft blue accent, flat fills, no
/// gradients or glow shadows.
enum Theme {
    static let accent = Color(hex: 0x6C93E8)
    static let accentInk = Color(hex: 0x0D1A33)
    static let good = Color(hex: 0x59C77E)
    static let warn = Color(hex: 0xE3A93C)
    static let bad = Color(hex: 0xEF6F5E)

    static let panelRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let rowSpacing: CGFloat = 2
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A flat accent-filled pill button — no gradient, no glow.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(kind == .primary ? .clear : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
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
        case .danger: return Theme.bad
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
