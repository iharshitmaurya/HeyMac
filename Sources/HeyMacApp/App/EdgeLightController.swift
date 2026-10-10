import AppKit
import SwiftUI

@MainActor
final class EdgeLightController {
    static let shared = EdgeLightController()
    
    private var window: NSPanel?
    private let elevated = LockScreenSpace()
    private var isVisible = false

    func show() {
        guard !isVisible else { return }
        isVisible = true

        let screen = NotchGeometry.preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if window == nil {
            let panel = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.isFloatingPanel = true
            panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            
            let view = NSHostingView(rootView: EdgeLightView())
            panel.contentView = view
            self.window = panel
        }

        guard let window = self.window else { return }
        window.setFrame(screenFrame, display: true)
        
        elevated?.show(window)
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1.0
        }
    }

    func hide() {
        guard isVisible, let window = self.window else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isVisible else { return }
                self.elevated?.hide(window)
                window.orderOut(nil)
            }
        })
    }
}

/// A soft, glowing curved border mimicking native MacBook screen illumination (like Photo Booth / Studio Light).
struct EdgeLightView: View {
    var body: some View {
        ZStack {
            // Soft ambient glow spreading inward and outward
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 50)
                .blur(radius: 18)

            // Bright core illumination
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 32)
                .blur(radius: 2)
        }
        .edgesIgnoringSafeArea(.all)
    }
}
