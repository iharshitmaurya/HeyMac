import AppKit
import SwiftUI

/// The post-unlock toast: a pill that appears under the notch and fades after a beat — the
/// same payoff Face ID shows on iPhone/iPad after a successful unlock. A floating NSPanel
/// (not a SwiftUI `Window`) because a menu-bar-only app needs precise control over level and
/// position, and the panel must survive across desktop spaces and full-screen apps.
@MainActor
final class UnlockHUD {
    static let shared = UnlockHUD()

    private lazy var panel: NSPanel = makePanel()
    private var dismissWork: DispatchWorkItem?

    func showUnlocked() {
        dismissWork?.cancel()

        let size = CGSize(width: 190, height: 56)
        panel.contentView = NSHostingView(rootView: HUDContent())
        position(panel, size: size)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func dismiss() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func position(_ panel: NSPanel, size: CGSize) {
        guard let screen = NSScreen.main else { return }
        let notchInset = max(screen.safeAreaInsets.top, 8)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - notchInset - size.height - 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }
}

private struct HUDContent: View {
    var body: some View {
        HStack(spacing: 10) {
            MatchFeedbackView(state: .success)
            Text("Face Unlocked")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
