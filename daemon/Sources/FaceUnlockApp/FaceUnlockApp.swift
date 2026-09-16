import AppKit
import SwiftUI
import FaceUnlockEngine

@main
struct FaceUnlockApp: App {
    private let model: AppModel

    init() {
        if CommandLine.arguments.contains("--self-check") {
            let problems = SelfCheck.run()
            for problem in problems { FileHandle.standardError.write(Data("self-check: \(problem)\n".utf8)) }
            print(problems.isEmpty ? "self-check passed" : "self-check failed (\(problems.count) problems)")
            exit(problems.isEmpty ? 0 : 1)
        }
        model = AppModel.shared
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuIconName)
        }
    }
}
