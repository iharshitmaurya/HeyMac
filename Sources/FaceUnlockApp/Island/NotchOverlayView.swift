//  The island itself: a black outline that grows out of the notch, or slides down as a
//  pill on Macs without one. It only reads the controller; every animated flag is flipped
//  there inside `withAnimation`, so this view keeps no state.

import SwiftUI

struct NotchOverlayView: View {
    let controller: NotchOverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: NotchPanelStyle { controller.geometry.style }
    private var closedSize: CGSize { controller.geometry.closedSize }
    private var isExpanded: Bool { controller.isExpanded }
    private var isCompact: Bool { controller.activeStyle == .minimal }
    private var onNotch: Bool { style == .notch }

    /// The outline's target measurements for the current style and state.
    private struct Outline {
        var size: CGSize
        var topRadius: CGFloat
        var bottomRadius: CGFloat
    }

    private var outline: Outline {
        let closedCap = closedSize.height / 2 // half the height is exactly a capsule end
        guard isExpanded else {
            return Outline(size: closedSize,
                           topRadius: onNotch ? IslandMetrics.closedTopRadius : closedCap,
                           bottomRadius: onNotch ? IslandMetrics.closedBottomRadius : closedCap)
        }
        switch (isCompact, onNotch) {
        case (true, true):
            return Outline(size: CGSize(width: closedSize.width + IslandMetrics.compactFlank * 2,
                                        height: closedSize.height + IslandMetrics.compactHeightBump),
                           topRadius: IslandMetrics.compactTopRadius,
                           bottomRadius: IslandMetrics.compactBottomRadius)
        case (true, false):
            // A true capsule as it stretches: the radius follows the animating height.
            let size = IslandMetrics.compactPillSize
            return Outline(size: size, topRadius: size.height / 2, bottomRadius: size.height / 2)
        case (false, true):
            return Outline(size: IslandMetrics.notchOpenSize,
                           topRadius: IslandMetrics.openTopRadius,
                           bottomRadius: IslandMetrics.openBottomRadius)
        case (false, false):
            return Outline(size: IslandMetrics.pillOpenSize,
                           topRadius: IslandMetrics.pillOpenCornerRadius,
                           bottomRadius: IslandMetrics.pillOpenCornerRadius)
        }
    }

    /// Drawn wider than the body by the ear allowance, so the closed state lands on the real notch.
    private func frameSize(for outline: Outline) -> CGSize {
        CGSize(width: outline.size.width + IslandMetrics.earAllowance(topRadius: outline.topRadius, style: style),
               height: outline.size.height)
    }

    /// The window is top-aligned, so sliding is just where the top edge sits.
    private var verticalOffset: CGFloat {
        guard style == .pill else { return 0 }
        return controller.isPositioned ? IslandMetrics.pillTopGap
                                       : -(closedSize.height + IslandMetrics.pillOffscreenSlack)
    }

    private var pulse: (scale: CGFloat, opacity: Double) {
        guard !reduceMotion, controller.isPulseDimmed else { return (1, 1) }
        return (IslandMotion.pulseScale, IslandMotion.pulseOpacity)
    }

    @ViewBuilder private func content(topRadius: CGFloat) -> some View {
        if isCompact {
            MinimalUnlockView(
                media: controller.media,
                isUnlocked: controller.isLockOpen,
                // On a notch the ear takes `topRadius` of the margin before any real black starts.
                sideInset: IslandMetrics.compactEdgeInset + (onNotch ? topRadius : 0),
                glyphSize: onNotch ? IslandMetrics.compactNotchLockSize : IslandMetrics.compactLockSize,
                clipWidth: onNotch ? IslandMetrics.compactNotchClipWidth : IslandMetrics.compactClipWidth,
                clipInset: onNotch ? IslandMetrics.compactNotchClipInset : IslandMetrics.compactClipInset,
                pulseScale: pulse.scale,
                pulseOpacity: pulse.opacity
            )
        } else {
            ScanAnimationView(media: controller.media)
                .padding(onNotch ? IslandMetrics.notchPadding : IslandMetrics.pillPadding)
                .scaleEffect(pulse.scale)
                .opacity(pulse.opacity)
        }
    }

    var body: some View {
        let target = outline
        let frame = frameSize(for: target)
        content(topRadius: target.topRadius)
            // The content dissolves as the outline shrinks, rather than being clipped by it.
            .blur(radius: isExpanded ? 0 : 40)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.3)
            .frame(width: frame.width, height: frame.height)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: target.topRadius, bottomRadius: target.bottomRadius, style: style))
            // Only while expanded; otherwise a faint halo shows around the real notch.
            .shadow(color: .black.opacity(isExpanded ? 0.3 : 0), radius: 9)
            .offset(y: verticalOffset)
            // Reduce Motion: swap the springs and slides for a short fade.
            .transaction { if reduceMotion { $0.animation = $0.animation == nil ? nil : .easeOut(duration: 0.15) } }
            .frame(width: IslandMetrics.windowSize.width, height: IslandMetrics.windowSize.height, alignment: .top)
    }
}
