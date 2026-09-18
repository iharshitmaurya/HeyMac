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
        Text("App Lock").font(.system(size: 15.5, weight: .bold))

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lock selected apps with my face").font(.system(size: 13, weight: .semibold))
                Text("Turning this off asks for your face, Touch ID or password first.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.appLockEnabled }, set: { model.setAppLockEnabled($0) }))
                .labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        if model.appLockApps.isEmpty {
            Text("No apps locked yet.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(model.appLockApps) { app in
                    lockedRow(app)
                    if app.id != model.appLockApps.last?.id { Divider().padding(.leading, 12) }
                }
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        Button("Add App…") { picker.open() }.buttonStyle(PillButtonStyle(kind: .secondary))
            .sheet(isPresented: Binding(get: { picker.isOpen }, set: { picker.isOpen = $0 })) {
                AppPickerSheet(model: model, picker: picker)
            }

        Text("App Lock is a convenience, not a security boundary. Someone who can quit FaceUnlock from Activity Monitor can bypass it, and notification previews from locked apps may still appear.")
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lockedRow(_ app: LockedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: app.bundleID)).resizable().frame(width: 26, height: 26)
            Text(app.name).font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("", selection: Binding(
                get: { PolicyChoice(app.policy) },
                set: { model.setLockedAppPolicy($0.policy, for: app.bundleID) }
            )) {
                ForEach(PolicyChoice.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 190)
            Button {
                model.removeLockedApp(app.bundleID)
            } label: { Image(systemName: "minus.circle.fill") }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
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
        case .everyTime: return "Every time I switch to it"
        case .fiveMinutes: return "After 5 minutes"
        case .fifteenMinutes: return "After 15 minutes"
        case .focusLoss5: return "5 minutes after I leave it"
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
        VStack(spacing: 12) {
            Text("Choose apps to lock").font(.system(size: 14, weight: .bold))
            TextField("Search", text: Binding(get: { picker.search }, set: { picker.search = $0 }))
                .textFieldStyle(.roundedBorder)
            List(results) { app in
                Button {
                    model.addLockedApp(app)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 26, height: 26)
                        Text(app.name)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 300)
            Button("Done") { picker.isOpen = false }.buttonStyle(PillButtonStyle(kind: .primary))
        }
        .padding(18)
        .frame(width: 380)
    }
}

@MainActor
private func icon(for bundleID: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
    return NSWorkspace.shared.icon(forFile: url.path)
}
