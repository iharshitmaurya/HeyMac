import AppKit
import SwiftUI

@MainActor @Observable
final class ShieldModel {
    enum Phase: Equatable { case scanning, authenticating, needsAuth(String), unlocked }

    var appName = ""
    var icon: NSImage?
    var phase: Phase = .scanning
    /// The display that shows the text and buttons; the others are blur only.
    var primaryDisplayID: CGDirectDisplayID?
    var faceAvailable = true
    var onUseSystem: () -> Void = {}
    var onStopRecognition: () -> Void = {}
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(primary ? .clear : Color.white.opacity(0.4), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed && primary ? 0.85 : 1) : 0.45)
    }
}

/// The centered text and buttons, shared by the whole-screen and the app-only shield.
/// The headline is constant; only the status line below it changes with the phase.
struct ShieldContent: View {
    let model: ShieldModel

    private var unlocked: Bool { if case .unlocked = model.phase { return true }; return false }
    private var scanning: Bool { if case .scanning = model.phase { return true }; return false }
    private var authenticating: Bool { if case .authenticating = model.phase { return true }; return false }
    private var status: String {
        switch model.phase {
        case .scanning: return "You can use Touch ID or your Mac password at any time."
        case .authenticating: return "Continue in the macOS authentication dialog."
        case .needsAuth(let message): return message
        case .unlocked: return "Unlocked"
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            ScrollView { content(compact: true) }
        }
        .padding(Spacing.lg)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? Spacing.sm : Spacing.lg) {
            if scanning {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
                    Image(systemName: "faceid").font(.system(size: compact ? 24 : 36)).foregroundStyle(.white)
                }.frame(width: compact ? 52 : 80, height: compact ? 52 : 80)
            } else if let icon = model.icon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: compact ? 40 : 64, height: compact ? 40 : 64).accessibilityHidden(true)
            }
            Text(unlocked ? L10n.text("Unlocked") : scanning ? L10n.text("Looking for your face…") : L10n.format("Unlock %@", model.appName))
                .font(.system(size: compact ? 20 : 27, weight: .semibold))
                .multilineTextAlignment(.center).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(status)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if scanning || authenticating { ProgressView().controlSize(.small).accessibilityLabel(scanning ? "Recognizing your face" : "Waiting for authentication") }
            if !unlocked {
            Button("Use Touch ID or Mac Password") { model.onUseSystem() }
                .buttonStyle(ShieldButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction).disabled(authenticating)
            if !scanning && !authenticating && model.faceAvailable {
                Button("Try Face Recognition") { model.onRetry() }.buttonStyle(ShieldButtonStyle(primary: false))
            }
            if scanning {
                Button("Stop Recognition") { model.onStopRecognition() }.buttonStyle(.plain).foregroundStyle(.white)
            }
            Button(L10n.format("Close %@ Without Unlocking", model.appName)) { model.onQuitApp() }
                .buttonStyle(.plain).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            }
            Label(L10n.format("Unlock to view %@.", model.appName), systemImage: "shield")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: 440).padding(.vertical, Spacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 6)
    }
}
