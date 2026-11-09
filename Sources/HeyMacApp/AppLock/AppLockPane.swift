import AppKit
import HeyMacEngine
import Observation
import SwiftUI

/// View-local state as an `@Observable` class: `@State` needs a macro plugin this
/// toolchain (Command Line Tools only) doesn't have.
@MainActor @Observable
final class AppPickerState {
    static let shared = AppPickerState()
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
    private let picker = AppPickerState.shared

    var body: some View {
        PaneTitle("App Lock", subtitle: "Choose which apps to protect and when they relock.")

        SettingsCard {
            FormRow(title: "Protect selected apps",
                    caption: model.appStatus.detail) {
                Toggle("Protect selected apps", isOn: Binding(get: { model.appLockEnabled }, set: { model.setAppLockEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            if model.appLockEnabled {
                RowDivider()
                FormRow(title: "Relaunch protection", caption: AppLockAgent.statusText) { relaunchChip }
            }
        }

        PaneSection {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(model.appLockEnabled ? "Protected apps" : "Selected apps · Protection off")
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

        CaptionText("“When switching to another app” relocks the app. Timed options show when their timer starts.")

        PaneSection(header: "App Lock coverage",
                    footnote: model.shieldMode == .appWindowsOnly
                        ? "Content may be briefly visible when app windows move or open."
                        : "App Lock hides app content. It doesn’t isolate the app or its data from other software.") {
            SettingsCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.md) { coverageChoice(.fullScreen); coverageChoice(.appWindowsOnly) }
                        VStack(spacing: Spacing.md) { coverageChoice(.fullScreen); coverageChoice(.appWindowsOnly) }
                    }
                    CaptionText(shieldCaption)
                }
                .padding(Spacing.lg)
            }
        }
    }

    private func coverageChoice(_ mode: ShieldMode) -> some View {
        Button { model.setShieldMode(mode) } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Surface.subtle)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.15)).frame(width: 65, height: 42)
                    if mode == .fullScreen { RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.22)) }
                    else { RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.3)).frame(width: 65, height: 42) }
                    Image(systemName: "lock").foregroundStyle(.primary)
                }.frame(height: 76).accessibilityHidden(true)
                Label(L10n.text(mode.title), systemImage: model.shieldMode == mode ? "largecircle.fill.circle" : "circle")
                    .font(Typography.rowTitle)
                CaptionText(mode == .fullScreen ? "Cover the display until you unlock." : "Keep the rest of your desktop in view.")
            }.padding(12).frame(minWidth: 145, maxWidth: .infinity, alignment: .leading)
                .background(Surface.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.shieldMode == mode ? Theme.accent : Surface.hairline, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(model.shieldMode == mode ? .isSelected : [])
    }

    private var shieldCaption: String {
        switch model.shieldMode {
        case .fullScreen:
            return "Cover the display until you unlock."
        case .appWindowsOnly:
            return "Keep the rest of your desktop in view. Hey Mac blurs the protected app’s windows."
        }
    }

    private var addButton: some View {
        Button("Add App…") { picker.open() }.buttonStyle(PillButtonStyle(kind: .secondary))
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "lock.square").font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No apps selected yet.").font(Typography.rowTitle)
            CaptionText("Add an app to get started.").multilineTextAlignment(.center)
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
        let policy = Picker(L10n.format("Relock policy for %@", app.name), selection: Binding(
            get: { PolicyChoice(app.policy) },
            set: { model.setLockedAppPolicy($0.policy, for: app.bundleID) }
        )) {
            ForEach(PolicyChoice.allCases) { Text(L10n.text($0.title)).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 260)

        let remove = Button { model.removeLockedApp(app.bundleID) } label: {
            Image(systemName: "minus.circle.fill").font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("Remove %@ from App Lock", app.name))
        .help(L10n.format("Remove %@ from App Lock", app.name))

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
        case .everyTime: return "When switching to another app"
        case .fiveMinutes: return "5 minutes after unlocking"
        case .fifteenMinutes: return "15 minutes after unlocking"
        case .focusLoss5: return "5 minutes after switching away"
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
    let picker: AppPickerState

    private var results: [InstalledApp] {
        let locked = Set(model.appLockApps.map(\.bundleID))
        return picker.installed.filter { app in
            !locked.contains(app.bundleID)
                && (picker.search.isEmpty || app.name.localizedCaseInsensitiveContains(picker.search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Choose apps to protect").font(.system(size: 20, weight: .semibold))
            CaptionText("Add one or more apps, then choose Done.")
            TextField("Find an app", text: Binding(get: { picker.search }, set: { picker.search = $0 }))
                .textFieldStyle(.roundedBorder)
            if results.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(picker.search.isEmpty ? "No apps available" : "No apps found").font(Typography.rowTitle)
                    CaptionText(picker.search.isEmpty ? "You’ve added all available apps." : "Try a different search.")
                    if !picker.search.isEmpty {
                        Button("Clear Search") { picker.search = "" }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    }
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
                            Text("Add").foregroundStyle(Theme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.format("Add %@ to App Lock", app.name))
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
    let state = AppPickerState()
    state.installed = InstalledApps.scan(roots: [URL(fileURLWithPath: "/System/Applications")])
    return AppPickerSheet(model: model, picker: state)
}

/// Snapshot-only: the no-results state.
@MainActor
func snapshotAppPickerEmpty(model: AppModel) -> some View {
    let state = AppPickerState()
    state.search = "zzzz"
    return AppPickerSheet(model: model, picker: state)
}
