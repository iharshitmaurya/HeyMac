import AppKit
import Observation
import SwiftUI
import FaceUnlockEngine

@MainActor
@Observable
final class SettingsState {
    var password = ""
    var passwordConfirm = ""
    var message: String?
}

struct SettingsView: View {
    let model: AppModel
    private let state = SettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Unlock sudo with my face", isOn: Binding(get: { model.sudoEnabled }, set: { model.setSudoEnabled($0) }))
                .disabled(!model.setupComplete || model.busy)
            Toggle("Unlock the lock screen with my face", isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreenEnabled($0) }))
                .disabled(!model.setupComplete)
            Toggle("Pause face unlock", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
            Toggle("Start FaceUnlock at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))

            Picker("How strict should matching be?", selection: Binding(get: { model.strictness }, set: { model.setStrictness($0) })) {
                ForEach(MatchStrictness.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            Text("Stricter means fewer false matches, but it may not recognize you in poor light.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Stored login password").bold()
                Text("Used only to type your password at the lock screen.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("Login password", text: Binding(get: { state.password }, set: { state.password = $0 }))
                SecureField("Confirm password", text: Binding(get: { state.passwordConfirm }, set: { state.passwordConfirm = $0 }))
                HStack {
                    Button("Save Password") { savePassword() }
                    if let message = state.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }

            Divider()

            HStack {
                Button("Open Log") { NSWorkspace.shared.open(model.log.url) }
                Button("Re-enroll My Face…") { model.reEnroll() }
                Spacer()
                Button("Remove My Face Data…", role: .destructive) { confirmRemoval() }
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .topLeading)
    }

    private func savePassword() {
        guard !state.password.isEmpty else {
            state.message = "Enter your login password."
            return
        }
        guard state.password == state.passwordConfirm else {
            state.message = "The two passwords don't match."
            return
        }
        state.message = model.saveLoginPassword(state.password) ?? "Saved."
        state.password = ""
        state.passwordConfirm = ""
    }

    private func confirmRemoval() {
        let alert = NSAlert()
        alert.messageText = "Remove your face data?"
        alert.informativeText = "This deletes your enrolled face, the stored login password and the encryption key, and turns off sudo face unlock. You can set FaceUnlock up again afterwards."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.removeAllData()
            model.windows.close(id: "settings")
        }
    }
}
