import AppKit
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBlock
            if !model.problems.isEmpty {
                Divider()
                ForEach(model.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }
            }
            Divider()
            toggleRow("Unlock sudo with my face", isOn: model.sudoEnabled) { model.setSudoEnabled($0) }
                .disabled(!model.setupComplete || model.busy)
            toggleRow("Unlock the lock screen", isOn: model.lockScreenEnabled) { model.setLockScreenEnabled($0) }
                .disabled(!model.setupComplete)
            toggleRow("Pause", isOn: model.paused) { model.setPaused($0) }
                .disabled(!model.setupComplete)
            Divider()
            if model.setupComplete {
                actionRow("Test Now…", shortcut: "⌘T") { model.openTest() }
                actionRow("Re-enroll My Face…", shortcut: nil) { model.reEnroll() }
            } else {
                actionRow("Set Up FaceUnlock…", shortcut: nil) { model.openSetup() }
            }
            actionRow("Settings…", shortcut: "⌘,") { model.openSettings() }
            Divider()
            actionRow("Quit FaceUnlock", shortcut: "⌘Q", tint: Theme.bad) { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 6)
        .frame(width: 302)
    }

    private var statusBlock: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: statusGlyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.system(size: 13.5, weight: .bold))
                Text(model.lastEvent).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var statusGlyph: String {
        if model.startupError != nil { return "exclamationmark.triangle.fill" }
        if !model.setupComplete { return "questionmark" }
        if model.paused { return "pause.fill" }
        return "checkmark"
    }

    private var statusTitle: String {
        if !model.setupComplete { return "Not Set Up Yet" }
        if model.paused { return "Face Unlock Is Paused" }
        return "Face Unlock Is On"
    }

    private func toggleRow(_ label: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5))
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private func actionRow(_ label: String, shortcut: String?, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(tint)
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}
