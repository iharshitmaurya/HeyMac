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
                        .font(Typography.caption)
                        .foregroundStyle(Theme.warnText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.xs)
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
            actionRow("Quit FaceUnlock", shortcut: "⌘Q", muted: true) { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, Spacing.sm)
        .frame(width: 302)
    }

    private var statusBlock: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: statusGlyph)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentInk)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                CaptionText(model.lastEvent)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
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

    private static let rowHeight: CGFloat = 28

    private func toggleRow(_ label: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Spacing.sm)
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: Self.rowHeight)
    }

    /// `muted` (Quit) uses the secondary label tone rather than red: quitting is not destructive.
    private func actionRow(_ label: String, shortcut: String?, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(muted ? Color.secondary : Color.primary)
                Spacer(minLength: Spacing.sm)
                if let shortcut {
                    Text(shortcut).font(Typography.caption).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, Spacing.sm + 2)
            .frame(minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        // ponytail: pressed-only feedback; hover needs per-row state (@State unavailable), add with an observable box when wanted.
        .buttonStyle(MenuRowStyle())
        .padding(.horizontal, Spacing.sm - 2)
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.10) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: Radius.style))
    }
}
