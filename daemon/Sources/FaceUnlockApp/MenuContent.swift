import AppKit
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
        ForEach(model.problems, id: \.self) { problem in
            Text("⚠︎ \(problem)")
        }
        Divider()

        Toggle("Unlock sudo with my face", isOn: Binding(get: { model.sudoEnabled }, set: { model.setSudoEnabled($0) }))
            .disabled(!model.setupComplete || model.busy)
        Toggle("Unlock the lock screen with my face", isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreenEnabled($0) }))
            .disabled(!model.setupComplete)
        Toggle("Pause", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
            .disabled(!model.setupComplete)
        Divider()

        if model.setupComplete {
            Button("Test Now…") { model.openTest() }
            Button("Re-enroll My Face…") { model.reEnroll() }
        } else {
            Button("Set Up FaceUnlock…") { model.openSetup() }
        }
        Button("Settings…") { model.openSettings() }
        Divider()
        Button("Quit FaceUnlock") { NSApplication.shared.terminate(nil) }
    }
}
