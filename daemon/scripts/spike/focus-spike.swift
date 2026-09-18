// Throwaway spike. Run: swift daemon/scripts/spike/focus-spike.swift activating|nonactivating
// Shows an opaque .mainMenu+2 panel, then calls LAContext. Observe whether the Touch ID /
// password sheet appears on top, takes input, and whether typing reaches the app behind.
import AppKit
import LocalAuthentication

let mode = CommandLine.arguments.dropFirst().first ?? "activating"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!
let panel = NSPanel(contentRect: screen.frame,
                    styleMask: mode == "nonactivating" ? [.borderless, .nonactivatingPanel] : [.borderless],
                    backing: .buffered, defer: false)
panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
panel.backgroundColor = NSColor(white: 0.05, alpha: 1)
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
panel.orderFrontRegardless()
if mode == "activating" { app.activate(ignoringOtherApps: true) }

DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    let context = LAContext()
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Spike: unlock test app") { ok, error in
        print("result ok=\(ok) error=\(String(describing: error))")
        DispatchQueue.main.async { app.terminate(nil) }
    }
}
app.run()
