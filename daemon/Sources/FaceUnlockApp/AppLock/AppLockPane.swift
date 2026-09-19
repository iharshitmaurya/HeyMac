import AppKit
import FaceUnlockEngine
import Observation
import SwiftUI

/// View-local state as an `@Observable` class: `@State` needs a macro plugin this
/// toolchain (Command Line Tools only) doesn't have.
@MainActor @Observable
private final class PickerState {
    var isOpen = false
    var search = ""
    var installed: [InstalledApp] = []

    func open() {
        installed = InstalledApps.scan()
        search = ""
        isOpen = true
    }
}

struct AppLockPane: View {
    let model: AppModel
    private let picker = PickerState()

    var body: some View {
        PaneTitle("App Lock")

        SettingsCard {
            FormRow(title: "Lock selected apps",
                    caption: "Turning this off asks for your face, Touch ID or password first.") {
                Toggle("Lock selected apps", isOn: Binding(get: { model.appLockEnabled }, set: { model.setAppLockEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            if model.appLockEnabled {
                RowDivider()
                FormRow(title: "Relaunch protection", caption: AppLockAgent.statusText) { relaunchChip }
            }
        }

        PaneSection {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Locked apps")
                Spacer(minLength: Spacing.sm)
                if !model.appLockApps.isEmpty { addButton }
            }
            if model.appLockApps.isEmpty {
                SettingsCard { emptyState }
            } else {
                SettingsCard {
                    ForEach(model.appLockApps) { app in
                        lockedRow(app)
                        if app.id != model.appLockApps.last?.id { RowDivider(inset: Surface.rowInset + IconSize.app + Spacing.md) }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { picker.isOpen }, set: { picker.isOpen = $0 })) {
            AppPickerSheet(model: model, picker: picker)
        }

        PaneSection(header: "Shield style") {
            SettingsCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Picker("Shield style", selection: Binding(get: { model.shieldMode }, set: { model.setShieldMode($0) })) {
                        ForEach(ShieldMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: .infinity)
                    CaptionText(shieldCaption)
                }
                .padding(Spacing.lg)
            }
        }
    }

    private var shieldCaption: String {
        switch model.shieldMode {
        case .fullScreen:
            return "Covers every display until you unlock; the strongest option."
        case .appWindowsOnly:
            return "Blurs just that app's windows and leaves other apps usable. It can lag slightly when you drag the window, and a new window may show for an instant."
        }
    }

    private var addButton: some View {
        Button("Add App…") { picker.open() }.buttonStyle(PillButtonStyle(kind: .secondary))
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "lock.square").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No locked apps yet").font(Typography.rowTitle)
            CaptionText("Choose an app to protect with your face.").multilineTextAlignment(.center)
            addButton.padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl).padding(.horizontal, Spacing.lg)
    }

    private var relaunchChip: StatusChip {
        let text = AppLockAgent.statusText
        if text.hasSuffix("is active") { return StatusChip(text: "Active", tone: .good) }
        if text.contains("needs approval") { return StatusChip(text: "Needs approval", tone: .warn) }
        return StatusChip(text: "Off", tone: .warn)
    }

    private func lockedRow(_ app: LockedApp) -> some View {
        let policy = Picker("Relock policy for \(app.name)", selection: Binding(
            get: { PolicyChoice(app.policy) },
            set: { model.setLockedAppPolicy($0.policy, for: app.bundleID) }
        )) {
            ForEach(PolicyChoice.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(minWidth: 150, idealWidth: 190, maxWidth: 190)

        let remove = Button { model.removeLockedApp(app.bundleID) } label: {
            Image(systemName: "minus.circle.fill").font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(app.name) from App Lock")
        .help("Remove \(app.name) from App Lock")

        let name = Text(app.name).font(Typography.rowTitle)
            .lineLimit(1).truncationMode(.tail).layoutPriority(1)
        let appIcon = Image(nsImage: icon(for: app.bundleID)).resizable()
            .frame(width: IconSize.app, height: IconSize.app).accessibilityHidden(true)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                appIcon
                name.frame(minWidth: 96, idealWidth: 96, maxWidth: .infinity, alignment: .leading)
                policy
                remove
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    appIcon
                    name
                    Spacer(minLength: Spacing.sm)
                    remove
                }
                policy.padding(.leading, IconSize.app + Spacing.md)
            }
        }
        .padding(.horizontal, Surface.rowInset).padding(.vertical, Spacing.sm)
        .frame(minHeight: 44)
    }
}

/// The three policies as fixed presets; the minute values are the defaults from the spec.
private enum PolicyChoice: String, CaseIterable, Identifiable {
    case everyTime, fiveMinutes, fifteenMinutes, focusLoss5

    var id: String { rawValue }

    init(_ policy: RelockPolicy) {
        switch policy {
        case .everyTime: self = .everyTime
        case .afterMinutes(let minutes): self = minutes >= 15 ? .fifteenMinutes : .fiveMinutes
        case .afterFocusLossMinutes: self = .focusLoss5
        }
    }

    var title: String {
        switch self {
        case .everyTime: return "Every time"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .focusLoss5: return "5 min after leaving"
        }
    }

    var policy: RelockPolicy {
        switch self {
        case .everyTime: return .everyTime
        case .fiveMinutes: return .afterMinutes(5)
        case .fifteenMinutes: return .afterMinutes(15)
        case .focusLoss5: return .afterFocusLossMinutes(5)
        }
    }
}

private struct AppPickerSheet: View {
    let model: AppModel
    let picker: PickerState

    private var results: [InstalledApp] {
        let locked = Set(model.appLockApps.map(\.bundleID))
        return picker.installed.filter { app in
            !locked.contains(app.bundleID)
                && (picker.search.isEmpty || app.name.localizedCaseInsensitiveContains(picker.search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose apps to lock").font(Typography.pageTitle)
            TextField("Search", text: Binding(get: { picker.search }, set: { picker.search = $0 }))
                .textFieldStyle(.roundedBorder)
            if results.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No matching apps").font(Typography.rowTitle)
                    CaptionText(picker.search.isEmpty ? "Every installed app is already locked." : "Try a different name.")
                }
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            } else {
                List(results) { app in
                    Button {
                        model.addLockedApp(app)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: IconSize.app, height: IconSize.app)
                                .accessibilityHidden(true)
                            Text(app.name).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: Spacing.sm)
                            Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(app.name) to App Lock")
                }
                .frame(minHeight: 240, idealHeight: 320, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Done") { picker.isOpen = false }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.lg + 2)
        .frame(minWidth: 380, idealWidth: 380)
    }
}

@MainActor
private func icon(for bundleID: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
    return NSWorkspace.shared.icon(forFile: url.path)
}

/// Snapshot-only: the "Add App" sheet content with a fixed list (read-only scan of /System/Applications).
@MainActor
func snapshotAppPickerSheet(model: AppModel) -> some View {
    let state = PickerState()
    state.installed = InstalledApps.scan(roots: [URL(fileURLWithPath: "/System/Applications")])
    return AppPickerSheet(model: model, picker: state)
}

/// Snapshot-only: the no-results state.
@MainActor
func snapshotAppPickerEmpty(model: AppModel) -> some View {
    let state = PickerState()
    state.search = "zzzz"
    return AppPickerSheet(model: model, picker: state)
}
