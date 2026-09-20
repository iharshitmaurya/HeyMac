import AppKit
import SwiftUI

/// Plain AppKit windows for the wizard and settings. A menu-bar-only app (LSUIElement)
/// has no reliable way to open SwiftUI `Window` scenes from outside a view, and this also
/// lets the app open the wizard by itself on first launch.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    /// `replacing`: a window with this id that is already open is closed and rebuilt, instead of just
    /// brought forward. `onClose` runs when the window closes by any route (its red button included).
    func show<Content: View>(id: String, title: String, size: CGSize, resizable: Bool = false, minSize: CGSize? = nil,
                              autosaveName: String? = nil, replacing: Bool = false, onClose: (() -> Void)? = nil,
                              @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            if replacing {
                existing.close() // its willClose handler drops it from `windows` and runs its onClose
            } else {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
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
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                if let window, self?.windows[id] === window { self?.windows[id] = nil }
                onClose?()
                if let observer { NotificationCenter.default.removeObserver(observer) }
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
