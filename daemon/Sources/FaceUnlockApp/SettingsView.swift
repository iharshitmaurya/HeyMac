import AppKit
import Observation
import SwiftUI
import FaceUnlockEngine

private enum SettingsPane: String, CaseIterable, Identifiable {
    case status = "Status"
    case access = "Sudo & Lock Screen"
    case face = "Face Data"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "checkmark.circle.fill"
        case .access: return "lock.fill"
        case .face: return "faceid"
        case .about: return "info.circle.fill"
        }
    }
}

/// Holds the selected sidebar item. A plain `@Observable` class rather than `@State`:
/// the `@State` property-wrapper macro needs a plugin this toolchain (Command Line
/// Tools only, no full Xcode) doesn't have.
@MainActor
@Observable
private final class SettingsSelection {
    var pane: SettingsPane = .status
}

/// A real macOS split view — sidebar left, one page right — the same shape as System
/// Settings, Mail, and Notes.
struct SettingsView: View {
    let model: AppModel
    private let selection = SettingsSelection()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 560, height: 460)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                Button {
                    selection.pane = item
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selection.pane == item ? Theme.accent : Color.primary.opacity(0.06))
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selection.pane == item ? Theme.accentInk : .secondary)
                        }
                        .frame(width: 22, height: 22)
                        Text(item.rawValue).font(.system(size: 12.5, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(selection.pane == item ? Color.primary.opacity(0.08) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 190)
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selection.pane {
                case .status: StatusPane(model: model)
                case .access: AccessPane(model: model)
                case .face: FacePane(model: model)
                case .about: AboutPane(model: model)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Status

private struct StatusPane: View {
    let model: AppModel

    var body: some View {
        Text("Status").font(.system(size: 15.5, weight: .bold))

        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentInk)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.setupComplete ? "Face Unlock Is On" : "Not Set Up Yet").font(.system(size: 14, weight: .bold))
                Text(statusSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(model.unlocksToday)").font(.system(size: 20, weight: .bold)).monospacedDigit()
                Text("unlocks today").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.accent.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(spacing: 0) {
            SettingsRow(title: "Start FaceUnlock at login") {
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).labelsHidden().tint(Theme.accent)
            }
            Divider().padding(.leading, 12)
            SettingsRow(title: "Pause face unlock", subtitle: "Falls back to your password immediately") {
                Toggle("", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) })).labelsHidden().tint(Theme.accent)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        Text("Open Log shows timestamps and match scores — never images or passwords.")
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
        Button("Open Log") { NSWorkspace.shared.open(model.log.url) }.buttonStyle(PillButtonStyle(kind: .secondary))
    }

    private var statusSubtitle: String {
        guard model.setupComplete else { return "Finish setup to turn it on" }
        var parts: [String] = []
        if model.sudoEnabled { parts.append("sudo") }
        if model.lockScreenEnabled { parts.append("lock screen") }
        return parts.isEmpty ? "nothing turned on" : parts.joined(separator: " · ") + " · active"
    }
}

// MARK: - Sudo & Lock Screen

private struct AccessPane: View {
    let model: AppModel

    var body: some View {
        Text("Sudo & Lock Screen").font(.system(size: 15.5, weight: .bold))

        VStack(spacing: 0) {
            SettingsRow(title: "Unlock sudo with my face", chip: sudoChip) {
                Toggle("", isOn: Binding(get: { model.sudoEnabled }, set: { model.setSudoEnabled($0) }))
                    .labelsHidden().tint(Theme.accent).disabled(model.busy)
            }
            Divider().padding(.leading, 12)
            SettingsRow(title: "Unlock the lock screen", chip: lockChip) {
                Toggle("", isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreenEnabled($0) })).labelsHidden().tint(Theme.accent)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 8) {
            Text("Matching strictness").font(.system(size: 13, weight: .semibold))
            Picker("", selection: Binding(get: { model.strictness }, set: { model.setStrictness($0) })) {
                ForEach(MatchStrictness.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Stricter means fewer false matches, but it may not recognize you in poor light.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock animation").font(.system(size: 13, weight: .semibold))
            Picker("", selection: Binding(get: { model.animationStyle }, set: { model.setAnimationStyle($0) })) {
                ForEach(UnlockAnimationStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Minimal widens the notch just enough for a lock and a small animation. Original opens a large panel. Picking one plays a preview.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    private var sudoChip: StatusChip {
        switch model.pamStatus {
        case .installed: return StatusChip(text: "Installed", tone: .good)
        case .partial: return StatusChip(text: "Needs reinstalling", tone: .warn)
        case .notInstalled: return StatusChip(text: "Not installed", tone: .idle)
        }
    }

    private var lockChip: StatusChip {
        model.accessibilityTrusted
            ? StatusChip(text: "Ready", tone: .good)
            : StatusChip(text: "Needs Accessibility permission", tone: .warn)
    }
}

// MARK: - Face Data

private struct FacePane: View {
    let model: AppModel

    var body: some View {
        Text("Face Data").font(.system(size: 15.5, weight: .bold))

        HStack(spacing: 14) {
            Circle().fill(Color.primary.opacity(0.08)).overlay(Circle().stroke(Color.primary.opacity(0.12))).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.setupComplete ? "Enrolled" : "Not enrolled").font(.system(size: 13.5, weight: .bold))
                if model.setupComplete {
                    Text("8 live samples, encrypted on this Mac").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        HStack(spacing: 10) {
            Button("Re-enroll My Face…") { model.reEnroll() }.buttonStyle(PillButtonStyle(kind: .secondary))
            Button("Remove My Face Data…") { confirmRemoval() }.buttonStyle(PillButtonStyle(kind: .danger))
        }
        Text("Removing your face data also turns off sudo and lock-screen unlock, and deletes the stored password.")
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
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

// MARK: - About

private struct AboutPane: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.accent)
                Image(systemName: "faceid").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accentInk)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("FaceUnlock").font(.system(size: 16, weight: .bold))
                Text("Version 1.0.0").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        Text("Face embedding: ArcFace (w600k_mbf), MIT. Liveness: MiniFASNetV2, minivision-ai/Silent-Face-Anti-Spoofing, Apache-2.0. Both run on-device — nothing is ever uploaded.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shared row

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var chip: StatusChip?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                if let chip { chip }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
