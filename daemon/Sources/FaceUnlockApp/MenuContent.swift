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
                            Text(problem).foregroundStyle(Theme.warnText).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(Typography.caption)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
            }
            divider
            toggleRow("Unlock the lock screen", icon: "lock.fill", isOn: model.lockScreenEnabled) { model.setLockScreenEnabled($0) }
                .disabled(!model.setupComplete)
            toggleRow("Pause", icon: "pause.circle", isOn: paused) { model.setPaused($0) }
                .disabled(!model.setupComplete)
            divider
            if !model.setupComplete {
                actionRow("Set Up FaceUnlock…", icon: "person.crop.circle.badge.plus", shortcut: nil) { model.openSetup() }
            }
            actionRow("Settings…", icon: "gearshape", shortcut: "⌘,") { model.openSettings() }
            divider
            actionRow("Quit FaceUnlock", icon: "rectangle.portrait.and.arrow.right", shortcut: "⌘Q", iconTint: Theme.badText) { NSApplication.shared.terminate(nil) }
        }
        .padding(.bottom, Spacing.sm)
        .frame(width: 302)
    }

    private var divider: some View {
        Divider().padding(.vertical, Spacing.xs)
    }

    private var attention: Bool { model.startupError != nil || !problems.isEmpty }

    private var header: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle().fill(avatarFill)
                Image(systemName: statusGlyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(avatarInk)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(model.lastEvent).font(Typography.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: Spacing.xs)
            if model.setupComplete {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(model.unlocksToday)").font(.system(size: 15, weight: .semibold).monospacedDigit())
                    Text("today").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.unlocksToday) unlocks today")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md + 2)
        .padding(.bottom, Spacing.md)
    }

    private var avatarFill: Color {
        if attention { return Theme.warn }
        if !model.setupComplete || paused { return Color.primary.opacity(0.14) }
        return Theme.accent
    }

    private var avatarInk: Color {
        if attention { return Theme.accentInk }
        if !model.setupComplete || paused { return .primary.opacity(0.75) }
        return Theme.accentInk
    }

    private var statusGlyph: String {
        if attention { return "exclamationmark" }
        if !model.setupComplete { return "questionmark" }
        if paused { return "pause.fill" }
        return "checkmark"
    }

    private var statusTitle: String {
        if !model.setupComplete { return "Not Set Up Yet" }
        if paused { return "Face Unlock Is Paused" }
        return "Face Unlock Is On"
    }

    private func iconView(_ name: String, tint: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(tint ?? Color.secondary)
            .opacity(0.8)
            .frame(width: Self.iconCol, alignment: .center)
    }

    private func toggleRow(_ label: String, icon: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HoverRow(id: label) {
            HStack(spacing: Spacing.md) {
                iconView(icon)
                Text(label).font(Typography.body).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Spacing.sm)
                Toggle(label, isOn: Binding(get: { isOn }, set: action))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .accessibilityLabel(label)
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: Self.rowHeight)
        }
    }

    private func actionRow(_ label: String, icon: String, shortcut: String?, iconTint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HoverRow(id: label) {
                HStack(spacing: Spacing.md) {
                    iconView(icon, tint: iconTint)
                    Text(label).font(Typography.body).lineLimit(1).truncationMode(.tail)
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
