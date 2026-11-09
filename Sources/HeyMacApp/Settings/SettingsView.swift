import AppKit
import Observation
import SwiftUI
import HeyMacEngine

enum SettingsPane: String, CaseIterable, Identifiable {
    case status = "Overview"
    case lockScreen = "Lock Screen"
    case appLock = "App Lock"
    case face = "Your Face"
    case appearance = "Appearance"
    case about = "About Hey Mac"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "shield"
        case .lockScreen: return "lock.fill"
        case .appLock: return "square.grid.2x2"
        case .face: return "faceid"
        case .appearance: return "sun.max"
        case .about: return "info.circle"
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
        .background(Surface.background)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.md) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                Text("Hey Mac").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            Text("YOUR MAC")
                .font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            ForEach(SettingsPane.allCases.filter { $0 != .about }) { item in
                SidebarItem(title: item.rawValue, systemImage: item.icon, isSelected: selection.pane == item) {
                    selection.pane = item
                }
                .accessibilityLabel(L10n.text(item.rawValue))
            }
            Spacer(minLength: 0)

            SidebarItem(title: SettingsPane.about.rawValue, systemImage: SettingsPane.about.icon,
                        isSelected: selection.pane == .about) {
                selection.pane = .about
            }
            .accessibilityLabel(L10n.text(SettingsPane.about.rawValue))
        }
        .padding(Spacing.md)
        .frame(width: 220)
        .background(Surface.sidebar)
    }

    /// Detail column: scrolls, content capped at 640pt and left-aligned so wide windows don't stretch controls.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let error = model.actionError { Label(L10n.text(error), systemImage: "exclamationmark.triangle").font(Typography.caption).foregroundStyle(Theme.warnText) }
                switch selection.pane {
                case .status: StatusPane(model: model)
                case .lockScreen: LockScreenPane(model: model)
                case .appLock: AppLockPane(model: model)
                case .face: FacePane(model: model)
                case .appearance: AppearancePane(model: model)
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
    var subtitle: String?
    init(_ text: String, subtitle: String? = nil) { self.text = text; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.text(text)).font(.system(size: 27, weight: .semibold)).tracking(-0.7)
                .lineLimit(2).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(L10n.text(subtitle)).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        Toggle(L10n.text(title), isOn: isOn)
            .labelsHidden().toggleStyle(.switch).tint(Theme.accent).disabled(disabled)
    }
}

// MARK: - Overview

private struct StatusPane: View {
    let model: AppModel
    private let selection = SettingsSelection.shared

    private var needsAttention: Bool { model.startupError != nil || !model.problems.isEmpty }
    private var allProtectionOff: Bool { !model.lockScreenEnabled && !model.appLockEnabled }

    var body: some View {
        PaneTitle("Overview", subtitle: "See what’s working and what needs attention.")

        SettingsCard(tinted: statusTone != .idle, tint: statusTone == .warn ? Theme.warn : Theme.good) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.lg) {
                    statusIconView
                    statusText
                        .layoutPriority(1)
                    Spacer(minLength: Spacing.sm)
                    StatusChip(text: statusLabel, tone: statusTone)
                }
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.lg) {
                        statusIconView
                        statusText
                    }
                    StatusChip(text: statusLabel, tone: statusTone)
                }
            }
            .padding(Spacing.lg)
            if let actionTitle {
                RowDivider()
                HStack {
                    Spacer()
                    Button(L10n.text(actionTitle)) {
                        model.perform(model.protectionStatus.action)
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
            }
        }

        if model.lastEvent != L10n.text("No checks yet") {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Latest result").font(Typography.rowTitle)
                    CaptionText(model.lastEvent)
                }
            }
            .padding(Spacing.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.subtle, in: RoundedRectangle(cornerRadius: Radius.md))
        }

        PaneSection(header: "Your protection") {
            SettingsCard {
                manageRow(title: "Lock Screen",
                          caption: lockCaption,
                          status: lockStatusLabel,
                          tone: lockStatusTone,
                          pane: .lockScreen)
                RowDivider()
                manageRow(title: "App Lock",
                          caption: appLockCaption,
                          status: appLockStatusLabel,
                          tone: appLockStatusTone,
                          pane: .appLock)
            }
        }

        PaneSection(header: "General") {
            SettingsCard {
                switchRow("Start at login", caption: "Open Hey Mac when you sign in.",
                          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                RowDivider()
                switchRow("Pause face recognition", caption: "You can still unlock protected apps with Touch ID or your Mac password.",
                          isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
            }
        }

        PaneSection(header: "Activity") {
            SettingsCard {
                FormRow(title: "Lock Screen unlocks today", caption: "Successful face unlocks on this Mac.") {
                    Text("\(model.unlocksToday)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                RowDivider()
                FormRow(title: "Recent activity", caption: model.lastEvent == L10n.text("No checks yet") ? "No unlock activity yet." : model.lastEvent) {
                    Button("Open Log…") { NSWorkspace.shared.open(model.log.url) }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
        }
    }

    private var statusTitle: String { model.protectionStatus.title }
    private var statusSubtitle: String { model.protectionStatus.detail }
    private var statusLabel: String { model.protectionStatus.label }
    private var statusTone: StatusChip.Tone { model.protectionStatus.tone }
    private var statusIcon: String { statusTone == .warn ? "exclamationmark" : model.paused ? "pause.fill" : "shield" }
    private var actionTitle: String? { model.protectionStatus.actionTitle }
    private var lockStatusLabel: String { model.lockStatus.label }
    private var lockStatusTone: StatusChip.Tone { model.lockStatus.tone }
    private var lockCaption: String { model.lockStatus.detail }
    private var appLockStatusLabel: String { model.appStatus.label }
    private var appLockStatusTone: StatusChip.Tone { model.appStatus.tone }
    private var appLockCaption: String { model.appStatus.detail }

    private var statusIconView: some View {
        ZStack {
            Circle().fill(statusTone == .good ? Theme.good.opacity(0.14) : statusTone == .warn ? Theme.warn.opacity(0.14) : Surface.subtle)
            Image(systemName: statusIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusTone == .good ? Theme.goodText : statusTone == .warn ? Theme.warnText : .secondary)
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.text(statusTitle)).font(.system(size: 20, weight: .semibold))
            Text(L10n.text(statusSubtitle)).font(Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func manageRow(title: String, caption: String, status: String, tone: StatusChip.Tone, pane: SettingsPane) -> some View {
        FormRow(title: title, caption: caption, chip: StatusChip(text: status, tone: tone)) {
            Button("Manage") { selection.pane = pane }
                .buttonStyle(PillButtonStyle(kind: .secondary))
                .accessibilityLabel(L10n.format("Manage %@", title))
        }
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
    var isSaving = false
}

private struct LockScreenPane: View {
    let model: AppModel
    private let form = PasswordForm()

    private var hasPassword: Bool {
        _ = form.saveCount
        return model.hasSavedPassword
    }

    var body: some View {
        PaneTitle("Lock Screen", subtitle: "Unlock your Mac with face recognition.")

        SettingsCard {
            switchRow("Unlock your Mac with face recognition", chip: lockChip,
                      isOn: Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreenEnabled($0) }))
            if !hasPassword, let reason = model.actionError {
                RowDivider()
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                    Text(L10n.text(reason)).foregroundStyle(Theme.warnText).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(Typography.caption)
                .padding(.horizontal, Surface.rowInset).padding(.vertical, Spacing.md)
            }
        }

        PaneSection(header: "Lock Screen requirements") {
            SettingsCard {
                FormRow(title: "Face setup", caption: model.setupComplete
                        ? "Face recognition is set up on this Mac."
                        : "Set up and test face recognition before enabling Lock Screen unlock.") {
                    HStack(spacing: Spacing.sm) {
                        StatusChip(text: model.setupComplete ? "Ready" : "Not set up", tone: model.setupComplete ? .good : .warn)
                        Button("Your Face") {
                            model.showSettings(.face)
                        }.buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
                RowDivider()
                FormRow(title: "Camera access", caption: "Needed for face recognition.") {
                    if model.cameraAuthorized {
                        StatusChip(text: "Allowed", tone: .good)
                    } else {
                        Button("Review Camera Access…") { model.openSystemSettings(anchor: "Privacy_Camera") }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
                RowDivider()
                FormRow(title: "Accessibility access", caption: "Lets Hey Mac enter your saved Mac login password after recognition.") {
                    if model.accessibilityTrusted {
                        StatusChip(text: "Allowed", tone: .good)
                    } else {
                        Button("Review Access…") { model.openSystemSettings(anchor: "Privacy_Accessibility") }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
                RowDivider()
                passwordForm
            }
        }

        CaptionText("After recognizing you, Hey Mac enters your saved Mac login password. Your Mac password and Touch ID continue to work as usual.")
        CaptionText("Face recognition uses a regular camera, without iPhone Face ID’s depth sensing.")

        CaptionText("Your saved password is encrypted on this Mac and never sent anywhere.")
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    passwordSummary.layoutPriority(1)
                    Spacer(minLength: Spacing.sm)
                    passwordActions
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    passwordSummary
                    passwordActions
                }
            }
            if !hasPassword || form.isChanging { fields }
        }
        .padding(Spacing.lg)
    }

    private var passwordSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Saved password").font(Typography.rowTitle)
            CaptionText(hasPassword ? "Encrypted on this Mac." : "Required for Lock Screen face unlock.")
            if hasPassword, !form.isChanging, let message = form.message {
                Text(L10n.text(message)).font(Typography.caption).foregroundStyle(Theme.goodText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var passwordActions: some View {
        if hasPassword, !form.isChanging {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) {
                    StatusChip(text: "Saved", tone: .good)
                    updatePasswordButton
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    StatusChip(text: "Saved", tone: .good)
                    updatePasswordButton
                }
            }
        } else {
            StatusChip(text: "Not saved", tone: .warn)
        }
    }

    private var updatePasswordButton: some View {
        Button("Update Saved Password…") { form.isChanging = true; form.message = nil }
            .buttonStyle(PillButtonStyle(kind: .secondary))
    }

    @ViewBuilder private var fields: some View {
        SecureField(hasPassword ? "New login password" : "Login password",
                    text: Binding(get: { form.password }, set: { form.password = $0 }))
            .textFieldStyle(.roundedBorder)
        SecureField("Confirm password", text: Binding(get: { form.confirm }, set: { form.confirm = $0 }))
            .textFieldStyle(.roundedBorder)
        HStack(spacing: Spacing.md) {
            Button(L10n.text(hasPassword ? "Update Password" : "Save Password")) { Task { await save() } }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(form.password.isEmpty || form.isSaving)
            if hasPassword {
                Button("Cancel") { form.isChanging = false; form.password = ""; form.confirm = ""; form.message = nil }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            if let message = form.message {
                Text(L10n.text(message)).font(Typography.caption)
                    .foregroundStyle(form.messageIsError ? Theme.badText : Theme.goodText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func save() async {
        guard !form.isSaving else { return }
        guard form.password == form.confirm else {
            form.message = "The two passwords don't match."; form.messageIsError = true
            return
        }
        form.isSaving = true
        defer { form.isSaving = false }
        if let error = await model.saveLoginPassword(form.password) {
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

    private var lockChip: StatusChip { StatusChip(text: model.lockStatus.label, tone: model.lockStatus.tone) }

}

// MARK: - Face Data

private struct FacePane: View {
    let model: AppModel

    var body: some View {
        PaneTitle("Your Face", subtitle: "Use the same face setup for Lock Screen and App Lock.")

        statusCard

        PaneSection(header: "Face recognition") {
            SettingsCard {
                FormRow(title: "Test face recognition", caption: "Check your lighting, then see if Hey Mac recognizes you.") {
                    Button("Test Face Recognition…") { model.openTest() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                        .disabled(!model.setupComplete)
                }
                RowDivider()
                FormRow(title: "Face setup", caption: model.setupComplete
                        ? "Verify it’s you, capture new face data, then test recognition."
                        : "Capture a few clear samples to set up face recognition.") {
                    Button(L10n.text(model.setupComplete ? "Set Up Again…" : "Set Up Face Recognition…")) {
                        model.setupComplete ? model.reEnroll() : model.openSetup()
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                RowDivider()
                FormRow(title: "Camera access", caption: model.cameraAuthorized
                        ? "Available for face recognition."
                        : "Allow camera access to use face recognition.") {
                    if model.cameraAuthorized {
                        StatusChip(text: "Allowed", tone: .good)
                    } else {
                        Button("Review Camera Access…") { model.openSystemSettings(anchor: "Privacy_Camera") }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }
        }

        PaneSection(header: "Face match requirement", footnote: strictnessFootnote) {
            SettingsCard {
                CaptionText("Applies to Lock Screen and App Lock.").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Spacing.lg).padding(.top, Spacing.md)
                Picker("Face match requirement", selection: Binding(get: { model.strictness }, set: { model.setStrictness($0) })) {
                    ForEach(MatchStrictness.allCases, id: \.self) { level in Text(L10n.text(matchLabel(level))).tag(level) }
                }
                .pickerStyle(.segmented).labelsHidden().padding(Spacing.lg)
            }
        }

        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            CaptionText("Your face data is encrypted and stored on this Mac, not as photos. The encryption key is kept in your Mac’s Keychain.")
        }
        .padding(.horizontal, Spacing.xs)

        if model.setupComplete {
            Button("Remove Face Data…") { confirmRemoval() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.badText)
                .accessibilityHint("Removes your face data and turns off Lock Screen face unlock.")
        }
    }

    private func matchLabel(_ level: MatchStrictness) -> String {
        switch level {
        case .relaxed: return "Lower"
        case .normal: return "Standard"
        case .strict: return "Higher"
        }
    }

    private var strictnessFootnote: String {
        switch model.strictness {
        case .relaxed: return "A lower match requirement may make recognition easier, with a greater risk of false matches."
        case .normal: return "The standard match requirement. Recognition depends on lighting and camera conditions."
        case .strict: return "A higher match requirement can reject more attempts, especially in difficult lighting."
        }
    }

    /// Enrolled: a teal confirmation. Not enrolled: a direct setup action.
    @ViewBuilder private var statusCard: some View {
        FaceCard(fill: Surface.card, stroke: Surface.hairline) {
            VStack(spacing: Spacing.md) {
                FaceIconCircle(icon: "faceid", tint: Theme.good, ink: Theme.goodText)
                Text(L10n.text(model.faceStatus.title)).font(.system(size: 20, weight: .semibold))
                CaptionText(model.faceStatus.detail).multilineTextAlignment(.center)
                StatusChip(text: model.faceStatus.label, tone: model.faceStatus.tone)
                if let title = model.faceStatus.actionTitle {
                    Button(L10n.text(title)) { model.perform(model.faceStatus.action) }.buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }.frame(maxWidth: .infinity).padding(.vertical, Spacing.lg)
        }
    }

    /// Cancel is the default (Return) button; the destructive confirm is second and never the default.
    private func confirmRemoval() {
        let alert = NSAlert()
        alert.messageText = L10n.text("Remove your face data?")
        alert.informativeText = L10n.text("This deletes your enrolled face, the stored login password and the encryption key and turns off lock-screen face unlock. You can set Hey Mac up again afterwards.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("Cancel"))
        let remove = alert.addButton(withTitle: L10n.text("Remove"))
        remove.hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            model.removeAllData()
        }
    }
}

// MARK: - Appearance

@MainActor @Observable
private final class AnimationDemo {
    static let shared = AnimationDemo()
    var phase = "idle"
    var task: Task<Void, Never>?
    func replay(_ model: AppModel, reducedMotion: Bool, playNotch: Bool = true) {
        task?.cancel()
        if playNotch { NotchOverlayController.shared.preview(model.animationStyle) }
        phase = reducedMotion ? "success" : "scanning"
        task = Task { @MainActor in
            if !reducedMotion {
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                phase = "success"
            }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            phase = "idle"
        }
    }
}

private struct AppearancePane: View {
    let model: AppModel
    private let demo = AnimationDemo.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PaneTitle("Appearance", subtitle: "Choose the animation shown during face unlock.")
        SettingsCard {
            switchRow("Show unlock animation", caption: "A brief confirmation at the top of your screen.",
                      isOn: Binding(get: { model.animationEnabled }, set: { model.setAnimationEnabled($0) }))
        }
        PaneSection(header: "Unlock style", footnote: "The app follows your macOS appearance and reduced-motion preferences.") {
            SettingsCard {
                VStack(spacing: 18) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12).fill(Surface.subtle)
                        HStack(spacing: 26) {
                            Image(systemName: "lock.fill").foregroundStyle(.white)
                            Image(systemName: demo.phase == "success" ? "checkmark" : "faceid")
                                .foregroundStyle(demo.phase == "success" ? Theme.good : Theme.accent)
                        }
                        .font(.system(size: model.animationStyle == .minimal ? 18 : 28))
                        .frame(width: model.animationStyle == .minimal ? 160 : 220, height: model.animationStyle == .minimal ? 44 : 80)
                        .background(.black, in: RoundedRectangle(cornerRadius: 22))
                        .padding(.top, 18).opacity(model.animationEnabled ? 1 : 0)
                    }.frame(height: 130).accessibilityHidden(true)
                    CaptionText(!model.animationEnabled ? "Unlock animation is off." : demo.phase == "scanning" ? "Recognizing…" : demo.phase == "success" ? "Recognized." : "Choose a style, then replay.")
                    Picker("Unlock style", selection: Binding(get: { model.animationStyle }, set: {
                        model.setAnimationStyle($0)
                        demo.replay(model, reducedMotion: reduceMotion, playNotch: false)
                    })) {
                        ForEach(UnlockAnimationStyle.allCases) { style in Text(L10n.text(style.title)).tag(style) }
                    }.pickerStyle(.segmented).disabled(!model.animationEnabled)
                    Button("Replay animation") { demo.replay(model, reducedMotion: reduceMotion) }
                        .buttonStyle(PillButtonStyle(kind: .secondary)).disabled(!model.animationEnabled)
                }.padding(Spacing.lg)
            }
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
        PaneTitle("Hey Mac", subtitle: "Your face. Your Mac. Your privacy.")

        VStack(spacing: Spacing.md) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .accessibilityHidden(true)
            Text(L10n.format("Version %@", version)).font(Typography.mono).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)

        SettingsCard {
            if AppUpdater.shared.isAvailable || AppModel.uiSnapshotMode {
                FormRow(title: "Software updates", caption: "Hey Mac asks before installing updates.") {
                    Button("Check for Updates…") { AppUpdater.shared.checkNow() }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .disabled(!AppUpdater.shared.canCheck && !AppModel.uiSnapshotMode)
                }
                RowDivider()
            }
            FormRow(title: "Open source", caption: "Explore the project on GitHub.") {
                Link("View GitHub ↗", destination: URL(string: "https://github.com/iharshitmaurya/HeyMac")!)
                    .font(Typography.body).foregroundStyle(Theme.accent)
            }
            RowDivider()
            FormRow(title: "Website", caption: "Visit the Hey Mac website.") {
                Link("Visit Website ↗", destination: URL(string: "https://heymacapp.com/")!)
                    .font(Typography.body).foregroundStyle(Theme.accent)
            }
        }
        if AppUpdater.shared.isAvailable || AppModel.uiSnapshotMode {
            SettingsCard {
                switchRow("Check for updates automatically", isOn: Binding(get: { AppUpdater.shared.checksAutomatically }, set: { AppUpdater.shared.setChecksAutomatically($0) }))
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
        alert.messageText = L10n.text("Uninstall Hey Mac?")
        alert.informativeText = L10n.text("This deletes your enrolled face, the stored login password, the encryption key, your settings and the app itself, and turns off lock-screen unlock and App Lock. It can't be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("Cancel"))
        let remove = alert.addButton(withTitle: L10n.text("Uninstall"))
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
                        Text(L10n.text(title)).font(Typography.sectionTitle)
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
        .accessibilityLabel(L10n.text(title))
        .accessibilityHint(L10n.text(caption))
    }
}

/// Dims slightly while pressed; the card itself supplies all the visuals.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
