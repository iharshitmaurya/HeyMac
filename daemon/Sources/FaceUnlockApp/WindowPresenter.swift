import AppKit
import SwiftUI

/// Plain AppKit windows for the wizard and settings. A menu-bar-only app (LSUIElement)
/// has no reliable way to open SwiftUI `Window` scenes from outside a view, and this also
/// lets the app open the wizard by itself on first launch.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, resizable: Bool = false, minSize: CGSize? = nil,
                              autosaveName: String? = nil, @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        if let minSize { window.contentMinSize = minSize }
        window.center()
        if let autosaveName { window.setFrameAutosaveName(autosaveName) } // restores a saved frame over the centered default
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
