import AppKit
import SwiftUI

private final class BlurPanel: NSPanel {
    var hostsContent = false
    let host: NSHostingView<ShieldContent>

    init(model: ShieldModel) {
        host = NSHostingView(rootView: ShieldContent(model: model))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = false // swallow clicks on the covered window

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.isEmphasized = false
        blur.maskImage = Self.roundedMask
        contentView = blur

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(ShieldStyle.tint).cgColor
        tint.layer?.cornerRadius = 12
        tint.layer?.masksToBounds = true
        tint.frame = blur.bounds
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        host.isHidden = true
        blur.addSubview(host)
    }

    private static let roundedMask: NSImage = {
        let r: CGFloat = 12
        let img = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }()

    func setHostsContent(_ on: Bool) {
        hostsContent = on
        host.isHidden = !on
    }

    override var canBecomeKey: Bool { hostsContent }
    override var canBecomeMain: Bool { false }
}

/// Blurs only the locked app's windows: one panel kept directly above each of its on-screen
/// windows, re-fitted by a fast poll. Can lag behind a window that is being dragged. There is
/// deliberately no timeout and no dismissal other than `dismiss()`.
@MainActor
final class AppWindowShield {
    static let pollInterval = 0.02

    private let model: ShieldModel
    private(set) var isShowing = false
    /// Called from the tick whenever the number of tracked windows changes (including 0 to n, n to 0).
    var onWindowCountChange: ((Int) -> Void)?

    private var pid: pid_t = 0
    private var timer: Timer?
    private var pool: [CGWindowID: BlurPanel] = [:]
    private var contentWindow: CGWindowID?
    private var lastCount = 0
    private var generation = 0

    init(model: ShieldModel) { self.model = model }

    func present(pid: pid_t) {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
        self.pid = pid
        generation += 1
        isShowing = true
        lastCount = 0
        // Reset through the animator with zero duration so a still-running dismiss fade is
        // cancelled; setting alphaValue directly would be overwritten when it lands on 0.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            for panel in pool.values { panel.animator().alphaValue = 1 }
        }
        timer?.invalidate()
        tick()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        isShowing = false
        generation += 1
        let mine = generation
        let fading = Array(pool.values)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            for panel in fading { panel.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == mine else { return }
                for panel in fading { panel.orderOut(nil); panel.alphaValue = 1 }
                self.pool.removeAll()
                self.contentWindow = nil
                self.lastCount = 0
            }
        })
    }

    private func tick() {
        guard isShowing else { return }
        let wins = WindowTracker.windows(forPID: pid)
        var live = Set<CGWindowID>()
        for win in wins {
            live.insert(win.number)
            let panel = pool[win.number] ?? BlurPanel(model: model)
            pool[win.number] = panel
            // Clamped to just above the menu bar so the notch island (.mainMenu + 3) always stays
            // on top. Consequence (documented limitation): windows of the locked app above this
            // level (pop-up menus, some HUDs) are not covered.
            let level = NSWindow.Level(rawValue: min(win.layer, NSWindow.Level.mainMenu.rawValue + 1))
            if panel.level != level { panel.level = level }
            if panel.frame != win.frame { panel.setFrame(win.frame, display: false) }
            panel.order(.above, relativeTo: Int(win.number))
        }
        for (number, panel) in pool where !live.contains(number) {
            panel.orderOut(nil)
            pool[number] = nil
        }
        // The text lives on the panel over the largest window; only that panel can become key.
        // Hysteresis: keep the current one unless another window is strictly larger (ties: lowest number).
        func area(_ w: TrackedWindow) -> CGFloat { w.frame.width * w.frame.height }
        let maxArea = wins.map(area).max() ?? 0
        var largest: CGWindowID?
        if let cur = contentWindow, let w = wins.first(where: { $0.number == cur }), area(w) >= maxArea {
            largest = cur
        } else {
            largest = wins.filter { area($0) == maxArea }.map(\.number).min()
        }
        if largest != contentWindow {
            if let old = contentWindow, let p = pool[old] {
                p.setHostsContent(false)
                if p.isKeyWindow { p.resignKey() }
            }
            contentWindow = largest
            if let n = largest, let p = pool[n] {
                p.setHostsContent(true)
                if NSApp.isActive { p.makeKey() }
            }
        }
        if wins.count != lastCount {
            lastCount = wins.count
            onWindowCountChange?(wins.count)
        }
    }
}
