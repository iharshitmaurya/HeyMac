import AppKit
import SwiftUI
import FaceUnlockEngine

@main
struct FaceUnlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model: AppModel

    init() {
        if CommandLine.arguments.contains("--self-check") {
            let problems = SelfCheck.run()
            for problem in problems { FileHandle.standardError.write(Data("self-check: \(problem)\n".utf8)) }
            print(problems.isEmpty ? "self-check passed" : "self-check failed (\(problems.count) problems)")
            exit(problems.isEmpty ? 0 : 1)
        }
        // The launch agent and the login item can both start us; only one copy may run.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
            exit(0)
        }
        model = AppModel.shared
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
