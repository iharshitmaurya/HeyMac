import AppKit
import SwiftUI

/// Hidden QA mode (`FaceUnlock --render-ui <dir>`): renders the real screens to PNG in light and dark,
/// hosted in an off-screen NSWindow, using sample state from `AppModel.uiSnapshotMode`.
/// Technique: NSHostingView in an NSWindow at x = -20000, ordered front, `cacheDisplay` into a
/// bitmap, with the window background colour painted behind the content. NSViewRepresentable content (the shield
/// blur, camera preview) renders empty/flat here.
@MainActor
enum UISnapshot {
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private static var lines: [String] = []
    private static var outputDir = ""

    static func run(outputDir dir: String) -> Never {
        outputDir = dir
        AppModel.uiSnapshotMode = true // before the first touch of AppModel.shared
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = AppModel.shared

        let paneNames = ["status", "lockscreen", "applock", "face", "about"]
        let settingsSizes = [(640, 480), (680, 520), (820, 620), (1000, 760)]
        for (i, pane) in paneNames.enumerated() {
            for (w, h) in settingsSizes {
                each { SettingsView(model: model, initialPaneIndex: i) }
                    render: { snap($0, screen: "settings-\(pane)", size: (w, h), dark: $1) }
            }
        }

        let stepNames = ["welcome", "camera", "enroll", "test", "features", "done"]
        for step in SetupFlow.Step.allCases {
            for (w, h) in [(720, 540), (900, 700)] {
                each { () -> SetupWizardView in
                    let flow = SetupFlow(model: model, startAt: step)
                    flow.cameraAuthorized = true
                    flow.cameraDenied = false
                    return SetupWizardView(flow: flow)
                } render: { snap($0, screen: "wizard-step\(step.rawValue + 1)", note: stepNames[step.rawValue], size: (w, h), dark: $1) }
            }
        }

        each { MenuContent(model: model) } render: { snap($0, screen: "menu", size: (302, nil), dark: $1) }
        each { MenuContent(model: model, previewPaused: true) } render: { snap($0, screen: "menu-paused", size: (302, nil), dark: $1) }
        each { MenuContent(model: model, previewProblems: ["Camera access is off", "Accessibility permission is needed to type at the lock screen"]) }
            render: { snap($0, screen: "menu-problems", size: (302, nil), dark: $1) }
        each { snapshotAppPickerSheet(model: model) } render: { snap($0, screen: "applock-picker", size: (380, nil), dark: $1) }
        each { snapshotAppPickerEmpty(model: model) } render: { snap($0, screen: "applock-picker-empty", size: (380, 340), dark: $1) }

        for (name, phase) in [("scanning", ShieldModel.Phase.scanning), ("needsauth", .needsAuth("Face not recognized. Try again or quit the app."))] {
            each { () -> AnyView in
                let shield = ShieldModel()
                shield.appName = "WhatsApp"
                shield.phase = phase
                return AnyView(ShieldContent(model: shield).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.12)))
            } render: { snap($0, screen: "shield-\(name)", size: (900, 500), dark: $1) }
        }

        let index = lines.joined(separator: "\n") + "\n"
        try? index.write(toFile: dir + "/index.txt", atomically: true, encoding: .utf8)
        print(lines.joined(separator: "\n"))
        print("\(lines.count) PNGs + index.txt in \(dir)")
        exit(0)
    }

    private static func each<V: View>(_ make: () -> V, render: (AnyView, Bool) -> Void) {
        for dark in [false, true] {
            // cacheDisplay leaves an opaque white ground, so paint the window background inside the view.
            render(AnyView(make().background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(dark ? .dark : .light)), dark)
        }
    }

    private static func snap(_ view: AnyView, screen: String, note: String? = nil, size: (Int, Int?), dark: Bool) {
        let host = NSHostingView(rootView: view)
        let fit = host.fittingSize
        host.sizingOptions = []
        let w = CGFloat(size.0)
        let h = CGFloat(size.1 ?? Int(ceil(fit.height)))
        if h <= 0 { FileHandle.standardError.write(Data("render-ui: zero height for \(screen)\n".utf8)) }
        let window = OffscreenWindow(contentRect: NSRect(x: -20000, y: 100, width: w, height: h),
                                     styleMask: [.titled], backing: .buffered, defer: false)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.appearance = appearance
        window.contentView = host
        window.setFrame(window.frameRect(forContentRect: NSRect(x: -20000, y: 100, width: w, height: h)), display: false)
        window.orderFront(nil)
        host.frame = NSRect(x: 0, y: 0, width: w, height: h)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let name = "\(screen)-\(Int(w))x\(Int(h))-\(dark ? "dark" : "light")"
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { window.close(); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let out = rep
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
        lines.append("\(name).png  screen=\(screen)\(note.map { "(\($0))" } ?? "")  size=\(Int(w))x\(Int(h))  appearance=\(dark ? "dark" : "light")")
        window.close()
    }
}
