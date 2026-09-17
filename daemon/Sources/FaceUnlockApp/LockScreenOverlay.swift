import AppKit
import SwiftUI
import FaceUnlockEngine

/// One small pill that follows a lock episode end to end: it appears the moment
/// FaceUnlock starts looking for a face (still locked), and morphs to a result once
/// one lands — matched and typed, or rejected.
///
/// The pill itself is an ordinary floating panel; what makes it visible *while the
/// screen is locked* is `LockScreenSpace`, which is only ever asked to place it there
/// for the locked phase. The moment the result is known, the panel is pulled back out
/// of that space — nothing stays pinned to the lock screen once we're done with it.
@MainActor
final class LockScreenOverlay {
    static let shared = LockScreenOverlay()

    private let elevated = LockScreenSpace()
    private lazy var panel: NSPanel = makePanel()
    private var dismissWork: DispatchWorkItem?
    private var isOnLockScreen = false

    func handle(_ event: EngineEvent) {
        switch event {
        case .lockScreenScanning: present(.idle, thenHideAfter: nil)
        case .lockScreenUnlocked: present(.success, thenHideAfter: 1.4)
        case .lockScreenPasswordRejected: present(.fail, thenHideAfter: 1.2)
        default: break
        }
    }

    private func present(_ state: MatchState, thenHideAfter delay: TimeInterval?) {
        dismissWork?.cancel()

        let hosting = NSHostingView(rootView: PillContent(state: state))
        panel.contentView = hosting
        position(fitting: hosting.fittingSize)

        // Unlocked means we're back on the ordinary desktop; anything still locked
        // (scanning, or a rejected password with the screen still up) needs the
        // lock-screen space to be visible at all.
        if state == .success {
            if isOnLockScreen, let elevated { elevated.hide(panel) }
            isOnLockScreen = false
        } else if !isOnLockScreen, let elevated {
            elevated.show(panel)
            isOnLockScreen = true
        }

        if panel.alphaValue < 1 || !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 1
        }

        guard let delay else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dismiss() {
        let panel = self.panel
        if isOnLockScreen, let elevated { elevated.hide(panel) }
        isOnLockScreen = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 56),
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

    private func position(fitting size: CGSize) {
        guard let screen = NSScreen.main else { return }
        let topInset = max(screen.safeAreaInsets.top, 8)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - topInset - size.height - 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

private struct PillContent: View {
    let state: MatchState

    var body: some View {
        HStack(spacing: 10) {
            MatchFeedbackView(state: state)
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .fixedSize()
    }

    private var label: String {
        switch state {
        case .idle: return "Looking for your face…"
        case .success: return "Face Unlocked"
        case .fail: return "Not Recognized"
        }
    }
}
