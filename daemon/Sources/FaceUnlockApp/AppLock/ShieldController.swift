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
    var isShowing: Bool { panelsUp || (windowShield?.isShowing ?? false) }
    private var panelsUp = false
    private var activeMode: ShieldMode = .fullScreen
    private var windowShield: AppWindowShield?
    private var panels: [CGDirectDisplayID: ShieldPanel] = [:]
    private var generation = 0
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPanels(orderFront: self?.panelsUp ?? false) }
        }
    }

    func prepare() {
        syncPanels(orderFront: false)
    }

    func present(appName: String, icon: NSImage?, pid: pid_t, mode: ShieldMode) {
        model.appName = appName
        model.icon = icon
        model.phase = .scanning
        let mouse = NSEvent.mouseLocation
        let primary = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        model.primaryDisplayID = primary?.displayID
        generation += 1
        activeMode = mode == .appWindowsOnly && pid > 0 ? .appWindowsOnly : .fullScreen
        for panel in panels.values { panel.alphaValue = 1 }
        if activeMode == .appWindowsOnly {
            let shield = windowShield ?? AppWindowShield(model: model)
            windowShield = shield
            shield.onWindowCountChange = { [weak self] count in
                guard let self, self.activeMode == .appWindowsOnly, shield.isShowing else { return }
                if count >= 1 { self.hidePanels() } else { self.showPanels() }
            }
            // No window yet (still launching): keep the whole screen covered until the first is tracked.
            if WindowTracker.windows(forPID: pid).isEmpty { showPanels() }
            shield.present(pid: pid)
        } else {
            showPanels()
        }
    }

    private func showPanels() {
        panelsUp = true
        syncPanels(orderFront: true)
        if let id = model.primaryDisplayID { panels[id]?.makeKey() }
    }

    private func hidePanels() {
        panelsUp = false
        for panel in panels.values { panel.orderOut(nil) }
    }

    func dismiss() {
        panelsUp = false
        windowShield?.dismiss()
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
        if panelsUp, model.primaryDisplayID.map({ !seen.contains($0) }) ?? true,
           let id = NSScreen.main?.displayID ?? seen.first {
            model.primaryDisplayID = id
            panels[id]?.makeKey()
        }
    }
}
