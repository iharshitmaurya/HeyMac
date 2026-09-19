import AppKit
import SwiftUI

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

private final class ShieldPanel: NSPanel {
    init(screen: NSScreen, displayID: CGDirectDisplayID, model: ShieldModel) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Above every app window and the menu bar, but below the notch island (.mainMenu + 3).
        level = .mainMenu + 2
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The blur is drawn by the content view. With macOS "Reduce Transparency" on,
        // NSVisualEffectView renders an opaque fallback, which is the safe behavior.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = NSHostingView(rootView: ShieldView(model: model, displayID: displayID))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One blurred panel per display. Panels are created ahead of time and only ordered in and
/// out, so showing the shield is a single `orderFront` — the fewer frames of the locked
/// app that can flash before it. There is deliberately no timeout and no other dismissal.
@MainActor
final class ShieldController {
    let model = ShieldModel()
    private(set) var isShowing = false
    private var panels: [CGDirectDisplayID: ShieldPanel] = [:]
    private var generation = 0
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPanels(orderFront: self?.isShowing ?? false) }
        }
    }

    func prepare() {
        syncPanels(orderFront: false)
    }

    func present(appName: String, icon: NSImage?) {
        model.appName = appName
        model.icon = icon
        model.phase = .scanning
        let mouse = NSEvent.mouseLocation
        let primary = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        model.primaryDisplayID = primary?.displayID
        generation += 1
        isShowing = true
        for panel in panels.values { panel.alphaValue = 1 }
        syncPanels(orderFront: true)
        if let id = primary?.displayID { panels[id]?.makeKey() }
    }

    func dismiss() {
        isShowing = false
        generation += 1
        let mine = generation
        let fading = Array(panels.values)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            for panel in fading { panel.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.generation == mine else { return }
                for panel in fading { panel.orderOut(nil); panel.alphaValue = 1 }
            }
        })
    }

    /// Creates panels for new displays, drops panels for removed ones, and refits the rest.
    private func syncPanels(orderFront: Bool) {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let panel = panels[id] ?? ShieldPanel(screen: screen, displayID: id, model: model)
            panels[id] = panel
            panel.setFrame(screen.frame, display: true)
            if orderFront { panel.orderFrontRegardless() }
        }
        for id in panels.keys where !seen.contains(id) {
            panels[id]?.orderOut(nil)
            panels[id] = nil
        }
        // The content display may have been unplugged; move it to a live one so the
        // message and buttons stay reachable.
        if isShowing, model.primaryDisplayID.map({ !seen.contains($0) }) ?? true,
           let id = NSScreen.main?.displayID ?? seen.first {
            model.primaryDisplayID = id
            panels[id]?.makeKey()
        }
    }
}
