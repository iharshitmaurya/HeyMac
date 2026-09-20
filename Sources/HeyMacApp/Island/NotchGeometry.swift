//  Measurements and timings for the notch island. Numbers only: no windows, no views.

import AppKit
import CoreGraphics
import SwiftUI

/// Which outline the island uses on a given display.
enum NotchPanelStyle {
    /// Flush with the top edge, with concave ears blending into the menu bar.
    case notch
    /// A floating capsule for Macs without a notch.
    case pill
}

/// What the current display looks like: the notch's real size, or a stand-in capsule.
struct NotchGeometry {
    let closedSize: CGSize
    let isPhysicalNotch: Bool

    var style: NotchPanelStyle { isPhysicalNotch ? .notch : .pill }

    /// The cutout's width is whatever the two menu-bar halves leave over. Right after wake that
    /// subtraction can come out implausibly small, so it is floored.
    private static let widthFloor: CGFloat = 200

    static func measure(_ screen: NSScreen) -> NotchGeometry {
        let cutoutHeight = screen.safeAreaInsets.top
        guard cutoutHeight > 0 else {
            return NotchGeometry(closedSize: IslandMetrics.pillClosedSize, isPhysicalNotch: false)
        }
        let menuBarHalves = (screen.auxiliaryTopLeftArea?.width ?? 0) + (screen.auxiliaryTopRightArea?.width ?? 0)
        let width = max(screen.frame.width - menuBarHalves, widthFloor)
        return NotchGeometry(closedSize: CGSize(width: width, height: cutoutHeight), isPhysicalNotch: true)
    }

    /// Prefer a display that has a notch; otherwise the main one.
    @MainActor
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    @MainActor
    static var current: NotchGeometry {
        guard let screen = preferredScreen else {
            return NotchGeometry(closedSize: IslandMetrics.pillClosedSize, isPhysicalNotch: false)
        }
        return measure(screen)
    }
}

/// Sizes, radii and insets.
enum IslandMetrics {
    // Full-size island (the scan animation is square, so the panel leaves room around it).
    static let notchOpenSize = CGSize(width: 220, height: 200)
    static let pillClosedSize = CGSize(width: 80, height: 24)
    static let pillOpenSize = CGSize(width: 180, height: 180)

    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 16
    static let openBottomRadius: CGFloat = 60
    static let pillOpenCornerRadius: CGFloat = 48

    /// The notch outline is `2 * topRadius` wider than its body, to make room for the ears.
    static func earAllowance(topRadius: CGFloat, style: NotchPanelStyle) -> CGFloat {
        style == .notch ? topRadius * 2 : 0
    }

    static let notchPadding = EdgeInsets(top: 26, leading: 40, bottom: 30, trailing: 40)
    static let pillPadding = EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)

    // Compact style: the island only widens, with a lock glyph on one side and a small clip on the other.
    /// Notch: body width is the cutout plus this much on each side (nothing may cover the cutout).
    static let compactFlank: CGFloat = 42
    /// The cutout's height is fixed, so this shows as extra black below it.
    static let compactHeightBump: CGFloat = 12
    static let compactTopRadius: CGFloat = 12
    static let compactBottomRadius: CGFloat = 22
    static let compactPillSize = CGSize(width: 150, height: 40)
    /// On a notch the ear already uses `topRadius` of this margin.
    static let compactEdgeInset: CGFloat = 4
    static let compactLockSize: CGFloat = 14
    static let compactNotchLockSize: CGFloat = 16
    static let compactClipWidth: CGFloat = 34
    static let compactNotchClipWidth: CGFloat = 40
    static let compactClipInset: CGFloat = 8
    static let compactNotchClipInset: CGFloat = 11

    static let pillTopGap: CGFloat = 3
    /// Parked pill sits this far above the screen so its shadow stays hidden too.
    static let pillOffscreenSlack: CGFloat = 20

    /// Room around the shape for its shadow.
    static let shadowPadding: CGFloat = 24
    private static let widestCompactContent: CGFloat = 360

    /// One fixed window holds every style; it is moved, never resized.
    static var windowSize: CGSize {
        let width = max(notchOpenSize.width, pillOpenSize.width, widestCompactContent) + shadowPadding * 2
        let height = max(notchOpenSize.height + shadowPadding, pillOpenSize.height + shadowPadding + pillTopGap)
        return CGSize(width: width, height: height)
    }
}

/// Springs, delays and holds.
enum IslandMotion {
    static let openSpring = (response: 0.45, damping: 0.7)
    static let closeSpring = (response: 0.45, damping: 1.0)

    static let pillSlide = 0.25
    /// Pill: it slides in first and grows after this delay; on the way out it shrinks first and slides after.
    static let pillEnterDelay = 0.16
    static let pillExitDelay = 0.18
    /// Long enough for the closing spring to settle before the window is hidden.
    static let collapse = 0.7
    static let lockMorph = 0.4

    // The "breathing" pulse while scanning.
    static let pulseScale: CGFloat = 0.97
    static let pulseOpacity = 0.65
    static let pulseHalfCycle = 0.4
    static let pulseHold = 0.05
    static let pulseSettle = 0.2
    /// Wait for the panel to finish opening before breathing.
    static let pulseStartDelay = 0.6

    /// A scan can never leave the island open forever; the engine gives up after 30 s.
    static let scanTimeout = 40.0

    static let successHold = 1.7
    /// Short on purpose: one attempt is allowed, so there's no retry to wait for.
    static let failureHold = 2.5
}
