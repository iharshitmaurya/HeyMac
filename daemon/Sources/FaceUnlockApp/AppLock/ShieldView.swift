import AppKit
import SwiftUI

@MainActor @Observable
final class ShieldModel {
    enum Phase: Equatable { case scanning, needsAuth(String), unlocked }

    var appName = ""
    var icon: NSImage?
    var phase: Phase = .scanning
    /// The display that shows the icon and buttons; the others are plain dark.
    var primaryDisplayID: CGDirectDisplayID?
    var onRetry: () -> Void = {}
    var onQuitApp: () -> Void = {}
}

struct ShieldView: View {
    let model: ShieldModel
    let displayID: CGDirectDisplayID

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(white: 0.05, alpha: 1))
            if model.primaryDisplayID == displayID { content }
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 14) {
            if let icon = model.icon {
                Image(nsImage: icon).resizable().frame(width: 72, height: 72)
            }
            Text(model.appName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
            if case .needsAuth = model.phase {
                HStack(spacing: 10) {
                    Button("Try Again") { model.onRetry() }.buttonStyle(PillButtonStyle(kind: .primary))
                    Button("Quit App") { model.onQuitApp() }.buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.top, 6)
            }
        }
    }

    private var status: String {
        switch model.phase {
        case .scanning: return "Looking for your face…"
        case .needsAuth(let message): return message
        case .unlocked: return "Unlocked"
        }
    }
}
