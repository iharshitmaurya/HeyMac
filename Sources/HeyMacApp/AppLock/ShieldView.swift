import AppKit
import SwiftUI

@MainActor @Observable
final class ShieldModel {
    enum Phase: Equatable { case scanning, needsAuth(String), unlocked }

    var appName = ""
    var icon: NSImage?
    var phase: Phase = .scanning
    /// The display that shows the text and buttons; the others are blur only.
    var primaryDisplayID: CGDirectDisplayID?
    var onRetry: () -> Void = {}
    var onQuitApp: () -> Void = {}
}

enum ShieldStyle {
    /// Black tint over the blur: raise to darken, lower to reveal more of the app.
    /// iOS-like look = window layout recognizable, text unreadable.
    static let tint = 0.30
}

struct ShieldBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ShieldView: View {
    let model: ShieldModel
    let displayID: CGDirectDisplayID
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            ShieldBlur()
            // Reduce Transparency makes the blur a flat fill; darken it so the white text stays readable.
            Color.black.opacity(reduceTransparency ? max(ShieldStyle.tint, 0.6) : ShieldStyle.tint)
            if model.primaryDisplayID == displayID { ShieldContent(model: model) }
        }
        .ignoresSafeArea()
    }

}

/// Shield-only button look: the scrim is always dark, whatever the system appearance.
private struct ShieldButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 7)
            .background(primary ? Theme.accent : Color.white.opacity(configuration.isPressed ? 0.28 : 0.16))
            .foregroundStyle(primary ? Theme.accentInk : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(primary ? .clear : Color.white.opacity(0.4), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed && primary ? 0.85 : 1) : 0.45)
    }
}

/// The centered text and buttons, shared by the whole-screen and the app-only shield.
/// The headline is constant; only the status line below it changes with the phase.
struct ShieldContent: View {
    let model: ShieldModel

    private var status: String {
        switch model.phase {
        case .scanning: return "Looking for your face…"
        case .needsAuth(let message): return message
        case .unlocked: return "Unlocked"
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md + Spacing.xs / 2) {
            Text("Hey Mac Required\nto open \(model.appName)")
                .font(.system(size: 26, weight: .regular))
                .lineSpacing(Spacing.sm)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            HStack(spacing: Spacing.sm) {
                switch model.phase {
                case .scanning:
                    ProgressView().controlSize(.small).colorScheme(.dark)
                case .unlocked:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                case .needsAuth:
                    EmptyView()
                }
                Text(status)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(minHeight: 20)
            if case .needsAuth = model.phase {
                HStack(spacing: Spacing.sm + 2) {
                    // Return retries; nothing on the shield is bound to Escape, so it can't be dismissed.
                    Button("Try Again") { model.onRetry() }
                        .buttonStyle(ShieldButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Try again")
                    Button("Quit App") { model.onQuitApp() }
                        .buttonStyle(ShieldButtonStyle(primary: false))
                        .accessibilityLabel("Quit \(model.appName)")
                }
                .padding(.top, Spacing.xs + 2)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hey Mac required to open \(model.appName). \(status)")
    }
}
