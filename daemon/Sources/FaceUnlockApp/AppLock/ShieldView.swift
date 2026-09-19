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

    var body: some View {
        ZStack {
            ShieldBlur()
            Color.black.opacity(ShieldStyle.tint)
            if model.primaryDisplayID == displayID { ShieldContent(model: model) }
        }
        .ignoresSafeArea()
    }

}

/// The centered text and buttons, shared by the whole-screen and the app-only shield.
struct ShieldContent: View {
    let model: ShieldModel

    var body: some View {
        VStack(spacing: 14) {
            Text("Face Unlock Required\nto open \(model.appName)")
                .font(.system(size: 26, weight: .regular))
                .lineSpacing(8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if case .needsAuth(let message) = model.phase {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 10) {
                    Button("Try Again") { model.onRetry() }.buttonStyle(PillButtonStyle(kind: .primary))
                    Button("Quit App") { model.onQuitApp() }.buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.top, 6)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6)
    }
}
