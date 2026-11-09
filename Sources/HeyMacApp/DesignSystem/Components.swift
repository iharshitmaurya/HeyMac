import SwiftUI

// Shared settings components. Pure SwiftUI, no @State. The row is named `FormRow` because
// SettingsView.swift still has a private `SettingsRow`; Wave 2 migrates views one by one.

/// Grouped card: Surface fill, Radius.lg, rows stacked with no spacing (use RowDivider between rows).
struct SettingsCard<Content: View>: View {
    var tinted: Bool = false
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tintColor = tint ?? Theme.accent
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tinted ? tintColor.opacity(0.1) : Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: Radius.style)
                    .stroke(tinted ? tintColor.opacity(0.25) : Surface.hairline, lineWidth: 1)
            )
    }
}

/// Title (never wraps), optional wrapping caption, optional chip, trailing control at natural size.
/// Falls back to a stacked layout (control below) when too narrow.
struct FormRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    var chip: StatusChip? = nil
    @ViewBuilder let trailing: () -> Trailing

    private var labels: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.text(title)).font(Typography.rowTitle)
                .lineLimit(2)
            if let caption { CaptionText(caption) }
            if let chip { chip }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.md) {
                // ideal width 200: a long caption wraps instead of forcing the stacked fallback
                labels.frame(idealWidth: 200, maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                Spacer(minLength: Spacing.sm)
                trailing().fixedSize()
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                labels
                trailing().fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Surface.rowInset)
        .padding(.vertical, Spacing.md)
        .frame(minHeight: 44)
    }
}

/// Divider aligned with the row label rather than the card edge.
struct RowDivider: View {
    var inset: CGFloat = Surface.rowInset
    var body: some View { Divider().padding(.leading, inset) }
}

struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(L10n.text(text)).font(Typography.sectionTitle)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.bottom, Spacing.xxs)
    }
}

/// The one caption style: wraps, never truncates.
struct CaptionText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(L10n.text(text)).font(Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Sidebar entry: a simple symbol and a selected row highlight.
struct SidebarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(L10n.text(title)).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Color.primary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(isSelected ? Theme.accent.opacity(0.09) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: Radius.style))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
