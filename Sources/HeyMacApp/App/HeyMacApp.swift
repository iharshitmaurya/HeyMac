import AppKit
import SwiftUI
import HeyMacEngine

@main
struct HeyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model: AppModel

    init() {
        if CommandLine.arguments.contains("--self-check") {
            let problems = SelfCheck.run()
            for problem in problems { FileHandle.standardError.write(Data("self-check: \(problem)\n".utf8)) }
            print(problems.isEmpty ? "self-check passed" : "self-check failed (\(problems.count) problems)")
            exit(problems.isEmpty ? 0 : 1)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-ui") {
            // QA harness: render the real screens to PNG with sample state, then exit. Runs before
            // the single-instance guard and before anything touches AppModel.shared.
            guard CommandLine.arguments.count > flag + 1 else {
                FileHandle.standardError.write(Data("usage: HeyMac --render-ui <outputDir>\n".utf8))
                exit(2)
            }
            let dir = CommandLine.arguments[flag + 1]
            MainActor.assumeIsolated { UISnapshot.run(outputDir: dir) }
        }
        // The launch agent and the login item can both start us; only one copy may run, and the
        // lowest pid keeps running so two simultaneous starts can never both yield. A duplicate
        // exits NON-zero: launchd only restarts a KeepAlive/SuccessfulExit=false job on failure, so
        // the agent job keeps retrying (every ~10 s) and, if the real instance is later killed,
        // the next retry becomes the running instance and relocks everything.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier < me }) {
            exit(1)
        }
        model = AppModel.shared
        AppUpdater.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
