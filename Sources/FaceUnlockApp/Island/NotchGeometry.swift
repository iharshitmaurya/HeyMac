//  Geometry and timing for the notch overlay.
//  Pure numbers plus screen measurement; no window or view knowledge.

import AppKit
import CoreGraphics
import SwiftUI

/// Which silhouette the overlay wears on a given screen.
enum NotchPanelStyle {
    /// Inverted top corners, flush with the screen's top edge.
    case notch
    /// Fully-rounded floating pill, detached from the edge (Macs without a notch).
    case pill
}

struct NotchGeometry {
    /// The physical notch's own size, or `pillClosedSize`.
    let closedSize: CGSize
    let isPhysicalNotch: Bool

    var style: NotchPanelStyle { isPhysicalNotch ? .notch : .pill }

    /// Sized for the square 432x432 scan animation plus breathing room.
    static let notchOpenSize = CGSize(width: 220, height: 200)
    static let pillClosedSize = CGSize(width: 80, height: 24)
    static let pillOpenSize = CGSize(width: 180, height: 180)

    /// Corner radii. The notch's top radius doubles as the width of the outward flare.
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 16
    static let openBottomRadius: CGFloat = 60
    static let pillOpenCornerRadius: CGFloat = 48

    /// The shape is drawn `2 * topRadius` wider than its body to fit the flare.
    static func flareAllowance(topRadius: CGFloat, style: NotchPanelStyle) -> CGFloat {
        style == .notch ? topRadius * 2 : 0
    }

    // MARK: Minimal style — the island only widens: lock glyph on one side, clip on the other.

    /// Notch: body width is the cutout plus this on each side (nothing may draw over the cutout itself).
    static let minimalNotchFlankWidth: CGFloat = 42
    /// Notch: the cutout's height can't change, so this shows as visible black below it.
    static let minimalNotchHeightBump: CGFloat = 12
    static let minimalNotchTopRadius: CGFloat = 12
    static let minimalNotchBottomRadius: CGFloat = 22
    static let minimalPillOpenSize = CGSize(width: 150, height: 40)
    /// In notch style the flare already occupies `topRadius` of this margin.
    static let minimalEdgeInset: CGFloat = 4
    static let minimalLockIconSize: CGFloat = 14
    static let minimalNotchLockIconSize: CGFloat = 16
    /// The clip is square and aspect-fit, so its size is `min(width, panelHeight - 2 * inset)`.
    static let minimalMediaWidth: CGFloat = 34
    static let minimalNotchMediaWidth: CGFloat = 40
    static let minimalMediaVerticalInset: CGFloat = 8
    static let minimalNotchMediaVerticalInset: CGFloat = 11
    static let minimalLockAnimationDuration = 0.4

    static let pillTopGap: CGFloat = 3
    /// Keeps the parked pill fully off-screen despite its shadow.
    static let pillOffscreenSlack: CGFloat = 20

    static let notchContentPadding = EdgeInsets(top: 26, leading: 40, bottom: 30, trailing: 40)
    static let pillContentPadding = EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)

    // MARK: Springs and choreography

    static let openSpring = (response: 0.45, damping: 0.7)
    static let closeSpring = (response: 0.45, damping: 1.0)
    static let pillSlideDuration = 0.25
    /// Pill: slide leads, expansion starts this long after. On exit, shrink leads and the slide follows.
    static let pillEnterExpansionDelay = 0.16
    static let pillExitSlideDelay = 0.18
    /// Long enough for the closing spring to settle before the window is hidden.
    static let collapseDuration = 0.7

    // MARK: Scan "breathing" pulse

    static let scanPulseScale: CGFloat = 0.97
    static let scanPulseOpacity = 0.65
    static let scanPulseHalfCycle = 0.4
    static let scanPulseHold = 0.05
    static let scanPulseSettle = 0.2
    /// Breathing starts only once the panel has finished expanding.
    static let scanPulseStartDelay = 0.6

    /// Safety net so a scan can never leave the island open forever; the engine's matching window is 30 s.
    static let scanTimeout = 40.0

    // MARK: Result holds

    static let successHold = 1.7
    /// Kept short: that hold exists so a hover can retry, and we allow one attempt.
    static let failureHold = 2.5

    // MARK: Window

    /// Room for `.shadow(radius: 9)` so it isn't clipped.
    static let shadowPadding: CGFloat = 24

    /// Widest a minimal notch island gets (cutout + flanks + flare), with margin.
    private static let minimalWindowContentWidth: CGFloat = 360

    /// One fixed window fits every style; it is never resized, only repositioned.
    static var windowSize: CGSize {
        let width = max(notchOpenSize.width, pillOpenSize.width, minimalWindowContentWidth) + shadowPadding * 2
        let height = max(notchOpenSize.height + shadowPadding, pillOpenSize.height + shadowPadding + pillTopGap)
        return CGSize(width: width, height: height)
    }

    /// The auxiliary-area arithmetic can read implausibly small mid-wake.
    private static let minimumNotchWidth: CGFloat = 200

    static func forScreen(_ screen: NSScreen) -> NotchGeometry {
        guard screen.safeAreaInsets.top > 0 else {
            return NotchGeometry(closedSize: pillClosedSize, isPhysicalNotch: false)
        }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let width = max(screen.frame.width - left - right, minimumNotchWidth)
        return NotchGeometry(closedSize: CGSize(width: width, height: screen.safeAreaInsets.top), isPhysicalNotch: true)
    }

    /// The display with a physical notch if there is one, else the main screen.
    @MainActor
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    @MainActor
    static var current: NotchGeometry {
        preferredScreen.map(forScreen)
            ?? NotchGeometry(closedSize: pillClosedSize, isPhysicalNotch: false)
    }
}
