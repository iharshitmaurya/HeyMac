//  The island itself: a black silhouette that grows out of the notch (or slides down as
//  a pill on Macs without one). It only reads the controller — every animated property
//  is flipped there inside `withAnimation`, so this view holds no state of its own.

import SwiftUI

struct NotchOverlayView: View {
    let controller: NotchOverlayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: NotchPanelStyle { controller.geometry.style }
    private var closedSize: CGSize { controller.geometry.closedSize }
    private var isExpanded: Bool { controller.isExpanded }

    private var isMinimal: Bool { controller.activeStyle == .minimal }

    private var openSize: CGSize {
        switch (isMinimal, style) {
        case (true, .notch):
            return CGSize(
                width: closedSize.width + NotchGeometry.minimalNotchFlankWidth * 2,
                height: closedSize.height + NotchGeometry.minimalNotchHeightBump
            )
        case (true, .pill): return NotchGeometry.minimalPillOpenSize
        case (false, .notch): return NotchGeometry.notchOpenSize
        case (false, .pill): return NotchGeometry.pillOpenSize
        }
    }

    private var topRadius: CGFloat {
        guard isExpanded else {
            // Half the height is exactly a capsule end.
            return style == .notch ? NotchGeometry.closedTopRadius : closedSize.height / 2
        }
        switch (isMinimal, style) {
        case (true, .notch): return NotchGeometry.minimalNotchTopRadius
        // The pill stays a true capsule as it stretches: radius tracks the animating height.
        case (true, .pill): return openSize.height / 2
        case (false, .notch): return NotchGeometry.openTopRadius
        case (false, .pill): return NotchGeometry.pillOpenCornerRadius
        }
    }

    private var bottomRadius: CGFloat {
        guard isExpanded else { return style == .notch ? NotchGeometry.closedBottomRadius : closedSize.height / 2 }
        switch (isMinimal, style) {
        case (true, .notch): return NotchGeometry.minimalNotchBottomRadius
        case (true, .pill): return openSize.height / 2
        case (false, .notch): return NotchGeometry.openBottomRadius
        case (false, .pill): return NotchGeometry.pillOpenCornerRadius
        }
    }

    /// Widened by the flare allowance so the closed state lands exactly on the physical notch.
    private var currentSize: CGSize {
        let body = isExpanded ? openSize : closedSize
        return CGSize(
            width: body.width + NotchGeometry.flareAllowance(topRadius: topRadius, style: style),
            height: body.height
        )
    }

    /// Top-aligned in the fixed window, so sliding is purely where the top edge sits.
    private var verticalOffset: CGFloat {
        guard style == .pill else { return 0 }
        return controller.isPositioned ? NotchGeometry.pillTopGap : -(closedSize.height + NotchGeometry.pillOffscreenSlack)
    }

    private var padding: EdgeInsets {
        style == .pill ? NotchGeometry.pillContentPadding : NotchGeometry.notchContentPadding
    }

    private var pulseScale: CGFloat { reduceMotion ? 1 : controller.isPulseDimmed ? NotchGeometry.scanPulseScale : 1 }
    private var pulseOpacity: Double { reduceMotion ? 1 : controller.isPulseDimmed ? NotchGeometry.scanPulseOpacity : 1 }

    @ViewBuilder private var scanContent: some View {
        if isMinimal {
            let notch = style == .notch
            MinimalUnlockView(
                media: controller.media,
                isUnlocked: controller.isLockOpen,
                // The notch's flare eats `topRadius` before any real black starts.
                edgeInset: NotchGeometry.minimalEdgeInset + (notch ? topRadius : 0),
                lockIconSize: notch ? NotchGeometry.minimalNotchLockIconSize : NotchGeometry.minimalLockIconSize,
                mediaWidth: notch ? NotchGeometry.minimalNotchMediaWidth : NotchGeometry.minimalMediaWidth,
                mediaVerticalInset: notch ? NotchGeometry.minimalNotchMediaVerticalInset : NotchGeometry.minimalMediaVerticalInset,
                pulseScale: pulseScale,
                pulseOpacity: pulseOpacity
            )
        } else {
            ScanAnimationView(media: controller.media)
                .padding(padding)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
        }
    }

    var body: some View {
        scanContent
            // Content dissolves as the panel shrinks instead of being clipped by it.
            .blur(radius: isExpanded ? 0 : 40)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.3)
            .frame(width: currentSize.width, height: currentSize.height)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius, style: style))
            // Only while expanded — otherwise a faint halo shows around the real notch.
            .shadow(color: .black.opacity(isExpanded ? 0.3 : 0), radius: 9)
            .offset(y: verticalOffset)
            // Reduce Motion: replace the controller's springs/slides with a short fade.
            .transaction { if reduceMotion { $0.animation = $0.animation == nil ? nil : .easeOut(duration: 0.15) } }
            .frame(width: NotchGeometry.windowSize.width, height: NotchGeometry.windowSize.height, alignment: .top)
    }
}
