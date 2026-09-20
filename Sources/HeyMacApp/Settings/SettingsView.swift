import AppKit
import Observation
import SwiftUI
import HeyMacEngine

enum SettingsPane: String, CaseIterable, Identifiable {
    case status = "Status"
    case lockScreen = "Lock Screen"
    case appLock = "App Lock"
    case face = "Face Data"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "checkmark.circle.fill"
        case .lockScreen: return "lock.fill"
        case .appLock: return "lock.square.fill"
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
final class SettingsSelection {
    static let shared = SettingsSelection()
    var pane: SettingsPane = .status
}

/// A real macOS split view — sidebar left, one page right — the same shape as System
/// Settings, Mail, and Notes.
struct SettingsView: View {
    let model: AppModel
    private let selection = SettingsSelection.shared

    /// `initialPaneIndex` (index into the sidebar order) is a snapshot-only hook; the app uses the default.
    init(model: AppModel, initialPaneIndex: Int = 0) {
        self.model = model
        selection.pane = SettingsPane.allCases[initialPaneIndex]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(SettingsPane.allCases) { item in
                SidebarItem(title: item.rawValue, systemImage: item.icon, isSelected: selection.pane == item) {
                    selection.pane = item
                }
                .accessibilityLabel(item.rawValue)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(width: 215)
    }

    /// Detail column: scrolls, content capped at 640pt and left-aligned so wide windows don't stretch controls.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                switch selection.pane {
                case .status: StatusPane(model: model)
                case .lockScreen: LockScreenPane(model: model)
                case .appLock: AppLockPane(model: model)
                case .face: FacePane(model: model)
                case .about: AboutPane(model: model)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pane title, one style everywhere.
struct PaneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typography.pageTitle).lineLimit(1).accessibilityAddTraits(.isHeader)
    }
}

/// One section: optional header, the content, optional footnote; identical spacing on every pane.
struct PaneSection<Content: View>: View {
    var header: String? = nil
    var footnote: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let header { SectionHeader(header) }
            content()
            if let footnote { CaptionText(footnote) }
        }
    }
}

/// A switch row inside a card: the title is the VoiceOver label.
private func switchRow(_ title: String, caption: String? = nil, chip: StatusChip? = nil, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
    FormRow(title: title, caption: caption, chip: chip) {
        Toggle(title, isOn: isOn)
            .labelsHidden().toggleStyle(.switch).tint(Theme.accent).disabled(disabled)
    }
}

// MARK: - Status

private struct StatusPane: View {
    let model: AppModel

    var body: some View {
        PaneTitle("Status")

        SettingsCard(tinted: true) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accentInk)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(model.setupComplete ? "Face unlock is on" : "Not set up yet")
                        .font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(statusSubtitle).font(Typography.caption).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(model.unlocksToday)").font(.system(size: 20, weight: .bold)).monospacedDigit()
                    Text("unlocks today").font(Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .fixedSize()
            }
            .padding(Spacing.lg)
        }

        PaneSection {
            SettingsCard {
                switchRow("Start Hey Mac at login",
                          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                RowDivider()
                switchRow("Pause face unlock", caption: "Falls back to your password immediately",
                          isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
            }
        }

        PaneSection {
            CaptionText("Open Log shows timestamps and match scores, never images or passwords.")
            Button("Open Log") { NSWorkspace.shared.open(model.log.url) }
                .buttonStyle(PillButtonStyle(kind: .secondary))
        }
    }

    private var statusSubtitle: String {
        guard model.setupComplete else { return "Finish setup to turn it on" }
        return model.lockScreenEnabled ? "Active for the lock screen" : "Nothing turned on yet"
    }
}

// MARK: - Lock Screen

/// Form state as an `@Observable` class (no `@State` on this toolchain).
@MainActor @Observable
private final class PasswordForm {
    var password = ""
    var confirm = ""
    var message: String?
    var messageIsError = false
    /// A saved password shows a compact row; the fields appear only while changing it.
    var isChanging = false
    /// Bumped after a save so the pane re-reads whether a password exists.
    var saveCount = 0
}

private struct LockScreenPane: View {
    let model: AppModel
    private let form = PasswordForm()

    private var hasPassword: Bool {
        _ = form.saveCount
        return model.runtime?.hasLoginPassword ?? false
    }

    var body: some View {
        PaneTitle("Lock Screen")

        SettingsCard {
            switchRow("Unlock the lock screen with my face", chip: lockChip,
                      isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreenEnabled($0) }))
            if !hasPassword, let reason = model.actionError {
                RowDivider()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text(reason).foregroundStyle(Theme.warnText).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(Typography.caption)
                .padding(.horizontal, Surface.rowInset).padding(.vertical, Spacing.md)
            }
        }

        PaneSection(header: "Login password",
                    footnote: "Your face can't unlock a Mac by itself, so Hey Mac types your password for you after it recognizes you. It's stored encrypted on this Mac and never sent anywhere.") {
            SettingsCard { passwordForm }
        }

        PaneSection(header: "Matching strictness",
                    footnote: "Stricter means fewer false matches, but it may not recognize you in poor light.") {
            SettingsCard {
                Picker("Matching strictness", selection: Binding(get: { model.strictness }, set: { model.setStrictness($0) })) {
                    ForEach(MatchStrictness.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(Spacing.lg)
            }
        }

        PaneSection(header: "Unlock animation",
                    footnote: "Minimal widens the notch just enough for a lock and a small animation. Original opens a large panel. Picking one plays a preview.") {
            SettingsCard {
                Picker("Unlock animation", selection: Binding(get: { model.animationStyle }, set: { model.setAnimationStyle($0) })) {
                    ForEach(UnlockAnimationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(Spacing.lg)
            }
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(hasPassword ? "Password saved" : "No password saved yet").font(Typography.rowTitle)
                    if hasPassword, !form.isChanging, let message = form.message {
                        Text(message).font(Typography.caption).foregroundStyle(Theme.goodText)
                    }
                }
                Spacer(minLength: Spacing.sm)
                StatusChip(text: hasPassword ? "Saved" : "Not saved", tone: hasPassword ? .good : .warn)
                if hasPassword, !form.isChanging {
                    Button("Change Password…") { form.isChanging = true; form.message = nil }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
            if !hasPassword || form.isChanging { fields }
        }
        .padding(Spacing.lg)
    }

    @ViewBuilder private var fields: some View {
        SecureField(hasPassword ? "New login password" : "Login password",
                    text: Binding(get: { form.password }, set: { form.password = $0 }))
            .textFieldStyle(.roundedBorder)
        SecureField("Confirm password", text: Binding(get: { form.confirm }, set: { form.confirm = $0 }))
            .textFieldStyle(.roundedBorder)
        HStack(spacing: Spacing.md) {
            Button(hasPassword ? "Update Password" : "Save Password") { save() }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(form.password.isEmpty)
            if hasPassword {
                Button("Cancel") { form.isChanging = false; form.password = ""; form.confirm = ""; form.message = nil }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            if let message = form.message {
                Text(message).font(Typography.caption)
                    .foregroundStyle(form.messageIsError ? Theme.badText : Theme.goodText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func save() {
        guard form.password == form.confirm else {
            form.message = "The two passwords don't match."; form.messageIsError = true
            return
        }
        if let error = model.saveLoginPassword(form.password) {
            form.message = error; form.messageIsError = true
            return
        }
        let wasBlocked = model.actionError != nil
        form.password = ""; form.confirm = ""
        form.message = "Password saved."; form.messageIsError = false
        form.isChanging = false
        form.saveCount += 1
        model.actionError = nil
        // They tried to turn the lock screen on and were stopped: finish what they asked for.
        if wasBlocked { model.setLockScreenEnabled(true) }
    }

    private var lockChip: StatusChip {
        if !hasPassword { return StatusChip(text: "Needs login password", tone: .warn) }
        return model.accessibilityTrusted
            ? StatusChip(text: "Ready", tone: .good)
            : StatusChip(text: "Needs Accessibility permission", tone: .warn)
    }
}

// MARK: - Face Data

private struct FacePane: View {
    let model: AppModel

    var body: some View {
        header

        statusCard

        VStack(spacing: Spacing.md) {
            FaceActionRow(icon: "faceid", title: "Test Now…",
                          caption: "Check if your face is recognized correctly.", tone: .neutral) { model.openTest() }
            FaceActionRow(icon: "arrow.triangle.2.circlepath", title: "Re-enroll My Face…",
                          caption: "Update your face data with a new scan.", tone: .neutral) { model.reEnroll() }
            FaceActionRow(icon: "trash", title: "Remove My Face Data…",
                          caption: "Removes your face data and disables face unlock.", tone: .danger) { confirmRemoval() }
        }
        .disabled(!model.setupComplete)

        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            CaptionText("Removing your face data also turns off lock-screen unlock, and deletes the stored password.")
        }
        .padding(.horizontal, Spacing.xs)
    }

    private var header: some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "faceid")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.accentText)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                PaneTitle("Face Data")
                CaptionText("Manage the face data used for unlocking your Mac.")
            }
            Spacer(minLength: 0)
        }
    }

    /// Enrolled: a green confirmation. Not enrolled: a prompt that starts setup.
    @ViewBuilder private var statusCard: some View {
        if model.setupComplete {
            FaceCard(fill: Theme.good.opacity(0.12), stroke: Theme.good.opacity(0.35)) {
                HStack(spacing: Spacing.lg) {
                    FaceIconCircle(icon: "checkmark.shield.fill", tint: Theme.good, ink: Theme.goodText)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Enrolled").font(Typography.sectionTitle)
                        CaptionText("Your face data is securely stored on this Mac.")
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            FaceActionRow(icon: "person.crop.circle.badge.plus", title: "Not enrolled",
                          caption: "Set up Hey Mac to enroll your face.", tone: .prompt) { model.openSetup() }
        }
    }

    /// Cancel is the default (Return) button; the destructive confirm is second and never the default.
    private func confirmRemoval() {
        let alert = NSAlert()
        alert.messageText = "Remove your face data?"
        alert.informativeText = "This deletes your enrolled face, the stored login password and the encryption key and turns off lock-screen face unlock. You can set Hey Mac up again afterwards."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let remove = alert.addButton(withTitle: "Remove")
        remove.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.removeAllData()
            model.windows.close(id: "settings")
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    let model: AppModel

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    var body: some View {
        PaneTitle("About")

        SettingsCard {
            HStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style).fill(Theme.accent)
                    Image(systemName: "faceid").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accentInk)
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Hey Mac").font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text("Version \(version)").font(Typography.mono).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
        }

        if AppUpdater.shared.isAvailable {
            PaneSection(header: "Updates") {
                SettingsCard {
                    FormRow(title: "Check for updates", caption: "Hey Mac checks about once a day and asks before installing.") {
                        Button("Check Now") { AppUpdater.shared.checkNow() }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                            .disabled(!AppUpdater.shared.canCheck)
                    }
                    RowDivider()
                    switchRow("Check automatically",
                              isOn: Binding(get: { AppUpdater.shared.checksAutomatically },
                                            set: { AppUpdater.shared.setChecksAutomatically($0) }))
                }
            }
        }

        PaneSection(header: "Uninstall") {
            SettingsCard {
                FormRow(title: "Uninstall Hey Mac",
                        caption: "Removes the app, your face data, saved password and settings from this Mac.") {
                    Button("Uninstall…") { confirmUninstall() }
                        .buttonStyle(PillButtonStyle(kind: .danger))
                }
            }
        }
    }

    /// Cancel is the default (Return) button; the destructive confirm is second and never the default.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Hey Mac?"
        alert.informativeText = "This deletes your enrolled face, the stored login password, the encryption key, your settings and the app itself, and turns off lock-screen unlock and App Lock. It can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        let remove = alert.addButton(withTitle: "Uninstall")
        remove.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            Task { await model.uninstall() }
        }
    }

}


// MARK: - Face Data pieces

private struct FaceCard<Content: View>: View {
    let fill: Color
    let stroke: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style).stroke(stroke, lineWidth: 1))
    }
}

private struct FaceIconCircle: View {
    let icon: String
    let tint: Color
    let ink: Color
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A tappable card: icon, title, one-line caption, chevron. `danger` tints it red; `prompt` amber.
private struct FaceActionRow: View {
    enum Tone { case neutral, danger, prompt }
    let icon: String
    let title: String
    let caption: String
    let tone: Tone
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var ink: Color {
        switch tone {
        case .neutral: return Theme.accentText
        case .danger: return Theme.badText
        case .prompt: return Theme.warnText
        }
    }
    private var tint: Color {
        switch tone {
        case .neutral: return Theme.accent
        case .danger: return Theme.bad
        case .prompt: return Theme.warn
        }
    }

    var body: some View {
        Button(action: action) {
            FaceCard(fill: tone == .neutral ? Surface.card : tint.opacity(0.10),
                     stroke: tone == .neutral ? Surface.hairline : tint.opacity(0.35)) {
                HStack(spacing: Spacing.lg) {
                    FaceIconCircle(icon: icon, tint: tint, ink: ink)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title).font(Typography.sectionTitle)
                            .foregroundStyle(tone == .danger ? Theme.badText : Color.primary)
                        CaptionText(caption)
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityHint(caption)
    }
}

/// Dims slightly while pressed; the card itself supplies all the visuals.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
