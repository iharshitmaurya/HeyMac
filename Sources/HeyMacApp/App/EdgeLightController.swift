import AppKit
import SwiftUI

@MainActor
final class EdgeLightController {
    static let shared = EdgeLightController()

    private var window: NSPanel?
    private let elevated = LockScreenSpace()
    private var isVisible = false
    private var isOnLockScreen = false

    func show(onLockScreen: Bool = true) {
        let screen = NotchGeometry.preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panel: NSPanel
        if let existing = self.window {
            panel = existing
        } else {
            let newPanel = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .screenSaver
            newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.ignoresMouseEvents = true
            newPanel.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: EdgeLightView())
            newPanel.contentView = hostingView
            self.window = newPanel
            panel = newPanel
        }

        panel.setFrame(screenFrame, display: true)

        if onLockScreen, !isOnLockScreen, let elevated {
            elevated.show(panel)
            isOnLockScreen = true
        } else if !onLockScreen, isOnLockScreen, let elevated {
            elevated.hide(panel)
            isOnLockScreen = false
        }

        guard !isVisible else {
            panel.orderFrontRegardless()
            return
        }

        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1.0
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible, let panel = self.window else { return }
        isVisible = false

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, !self.isVisible else { return }
                    if self.isOnLockScreen, let elevated = self.elevated {
                        elevated.hide(panel)
                        self.isOnLockScreen = false
                    }
                    panel.orderOut(nil)
                }
            })
        } else {
            if isOnLockScreen, let elevated {
                elevated.hide(panel)
                isOnLockScreen = false
            }
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }
}

/// A soft, glowing curved border mimicking native Studio Light display illumination.
struct EdgeLightView: View {
    var body: some View {
        GeometryReader { _ in
            let cornerRadius: CGFloat = 44
            ZStack {
                // Wide ambient glow to cast light onto the user's face
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color(red: 1.0, green: 0.98, blue: 0.94).opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 90
                    )
                    .blur(radius: 28)

                // Mid-tier diffusion
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 50)
                    .blur(radius: 12)

                // Bright core perimeter ribbon
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 28)
                    .blur(radius: 2)
            }
            .compositingGroup()
        }
        .edgesIgnoringSafeArea(.all)
    }
}
