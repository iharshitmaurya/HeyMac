import AppKit
import SwiftUI

/// Hover target shared by all rows. A singleton because the popover re-inits its views and this
/// toolchain has no `@State`. ponytail: one popover at a time; stale id if the popover closes while hovering (cleared on next exit).
@MainActor @Observable final class MenuHoverState {
    static let shared = MenuHoverState()
    var hoveredID: String?
}

struct MenuContent: View {
    let model: AppModel
    /// QA harness only: force paused/problems (AppModel's state is private(set)).
    var previewPaused: Bool?
    var previewProblems: [String]?

    private var paused: Bool { previewPaused ?? model.paused }
    private var problems: [String] { previewProblems ?? model.problems }
    private static let iconCol: CGFloat = 20
    private static let rowHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(problems, id: \.self) { problem in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                            Text(L10n.text(problem)).foregroundStyle(Theme.warnText).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(Typography.caption)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
            }
            divider
            toggleRow("Lock Screen", caption: lockScreenStatus, icon: "lock", isOn: model.lockScreenEnabled) { model.setLockScreenEnabled($0) }
                .disabled(!model.setupComplete)
            toggleRow("App Lock", caption: appLockStatus, icon: "square.grid.2x2", isOn: model.appLockEnabled) { model.setAppLockEnabled($0) }
            divider
            if let title = model.protectionStatus.actionTitle, model.protectionStatus.action != .resume {
                actionRow(title, icon: "arrow.forward.circle", shortcut: nil) { model.perform(model.protectionStatus.action) }
            }
            if model.setupComplete {
                actionRow(paused ? "Resume face recognition" : "Pause face recognition", icon: paused ? "play.circle" : "pause.circle", shortcut: nil) { model.setPaused(!paused) }
            }
            actionRow("Settings…", icon: "gearshape", shortcut: "⌘,") { model.openSettings() }
            if AppUpdater.shared.isAvailable {
                actionRow("Check for Updates…", icon: "arrow.down.circle", shortcut: nil) { AppUpdater.shared.checkNow() }
                    .disabled(!AppUpdater.shared.canCheck)
            }
            divider
            actionRow("Quit Hey Mac", icon: "rectangle.portrait.and.arrow.right", shortcut: "⌘Q") { NSApplication.shared.terminate(nil) }
        }
        .padding(.bottom, Spacing.sm)
        .frame(width: 302)
        .background(Color(light: 0xFFFFFF, dark: 0x242428))
    }

    private var divider: some View {
        Divider().padding(.vertical, Spacing.xs)
    }

    private var attention: Bool { model.startupError != nil || !problems.isEmpty }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hey Mac").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(statusTint).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(L10n.text(statusTitle)).font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    private var statusTint: Color { model.protectionStatus.tone == .warn ? Theme.warnText : model.protectionStatus.tone == .good ? Theme.goodText : .secondary }
    private var statusTitle: String { previewPaused == true ? "Face recognition is paused." : previewProblems?.isEmpty == false ? "Needs attention" : model.protectionStatus.title }
    private var lockScreenStatus: String { previewPaused == true ? "Face recognition paused" : model.lockStatus.label }
    private var appLockStatus: String { model.appStatus.tone == .good ? L10n.plural("App Lock protected apps", count: model.appLockApps.count) : model.appStatus.label }

    private func iconView(_ name: String, tint: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(tint ?? Color.secondary)
            .opacity(0.8)
            .frame(width: Self.iconCol, alignment: .center)
    }

    private func toggleRow(_ label: String, caption: String, icon: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HoverRow(id: label) {
            HStack(spacing: Spacing.md) {
                iconView(icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text(label)).font(Typography.body).lineLimit(1)
                    Text(L10n.text(caption)).font(Typography.caption).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
                Toggle(L10n.text(label), isOn: Binding(get: { isOn }, set: action))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .accessibilityLabel(L10n.text(label))
                    .accessibilityValue(L10n.format("%@, %@", L10n.text(isOn ? "On" : "Off"), L10n.text(caption)))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 52)
        }
    }

    private func actionRow(_ label: String, icon: String, shortcut: String?, iconTint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HoverRow(id: label) {
                HStack(spacing: Spacing.md) {
                    iconView(icon, tint: iconTint)
                    Text(L10n.text(label)).font(Typography.body).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Spacing.sm)
                    if let shortcut {
                        Text(shortcut).font(Typography.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: Self.rowHeight)
            }
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// Row chrome: 8pt highlight inset 6pt from the popover edges, driven by `MenuHoverState`.
private struct HoverRow<Content: View>: View {
    let id: String
    @ViewBuilder let content: Content
    var body: some View {
        let hover = MenuHoverState.shared
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: Radius.style)
                    .fill(hover.hoveredID == id ? Color.primary.opacity(0.08) : .clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hover.hoveredID = id } else if hover.hoveredID == id { hover.hoveredID = nil }
            }
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: Radius.style)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.08) : .clear)
                    .padding(.horizontal, 6)
            )
    }
}
