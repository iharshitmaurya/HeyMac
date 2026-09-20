//  Runs the island through one lock episode: opens on the still image while scanning,
//  plays the unlock or rejected clip, then collapses. The animated flags (`isExpanded`,
//  `isPositioned`, `isPulseDimmed`) are flipped here inside `withAnimation`, with real
//  `Task.sleep` gaps for the staggering, because chained `.animation(value:)` modifiers
//  don't stagger reliably.
//
//  The window is an ordinary click-through panel. `LockScreenSpace` is what makes it
//  visible on the lock screen, and only while the screen is still locked; once the unlock
//  lands the panel is pulled back out so nothing stays pinned there.

import AppKit
import HeyMacEngine
import Observation
import SwiftUI

@MainActor @Observable
final class NotchOverlayController {
    static let shared = NotchOverlayController()

    enum Phase { case closed, scanning, success, failure, collapsing }

    private(set) var phase: Phase = .closed
    private(set) var media: ScanMedia = .idle
    private(set) var geometry = NotchGeometry.current
    private(set) var isExpanded = false
    /// Pill only: parked on screen vs. slid off the top edge. The notch is always positioned.
    private(set) var isPositioned = false
    private(set) var isPulseDimmed = false
    /// Minimal style: the lock glyph flips open on success. Held open through the collapse.
    private(set) var isLockOpen = false
    /// Snapshotted when an episode opens, so changing the setting mid-episode can't resize the panel.
    private(set) var activeStyle = UnlockAnimationStyle.saved

    @ObservationIgnored private lazy var window = makeWindow()
    @ObservationIgnored private let elevated = LockScreenSpace()
    @ObservationIgnored private var isOnLockScreen = false
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    @ObservationIgnored private var scanTimeoutTask: Task<Void, Never>?

    func handle(_ event: EngineEvent) {
        switch event {
        case .lockScreenScanning: beginScanning()
        case .lockScreenUnlocked: finish(success: true)
        case .lockScreenPasswordRejected: finish(success: false)
        case .lockScreenScanEnded: cancelScanning()
        default: break
        }
    }

    // MARK: - Episode

    /// Opens on the still. The screen is locked here, so the panel goes into the lock space.
    func beginScanning(onLockScreen: Bool = true, style: UnlockAnimationStyle? = nil) {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()
        ensureOpen(onLockScreen: onLockScreen, style: style)
        isLockOpen = false
        media = .idle
        phase = .scanning
        startPulse()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(IslandMotion.scanTimeout))
            guard !Task.isCancelled else { return }
            self?.cancelScanning()
        }
    }

    /// Success has already unlocked the screen, so it plays on the desktop; a rejected
    /// password leaves the lock screen up, so failure stays where it is.
    func finish(success: Bool) {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()
        if phase == .closed || phase == .collapsing { ensureOpen(onLockScreen: !success) }
        stopPulse()
        media = success ? .success : .failure
        phase = success ? .success : .failure
        isLockOpen = success
        if success {
            place(onLockScreen: false)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
        let hold = success ? IslandMotion.successHold : IslandMotion.failureHold
        resolveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    /// Plays a full scan → unlock in `style` on the desktop, for the Settings picker.
    func preview(_ style: UnlockAnimationStyle) {
        guard phase == .closed else { return }
        beginScanning(onLockScreen: false, style: style)
        resolveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.finish(success: true)
        }
    }

    /// Closes the island quietly when an episode is abandoned before any result (no clip).
    func cancelScanning() {
        guard phase == .scanning else { return }
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()
        collapse()
    }

    private func collapse() {
        guard phase != .closed, phase != .collapsing else { return }
        phase = .collapsing
        stopPulse()
        transitionTask?.cancel()
        let isPill = geometry.style == .pill
        transitionTask = Task { [weak self] in
            withAnimation(Self.spring(IslandMotion.closeSpring)) { self?.isExpanded = false }
            if isPill {
                try? await Task.sleep(for: .seconds(IslandMotion.pillExitDelay))
                guard !Task.isCancelled else { return }
                withAnimation(Self.slide) { self?.isPositioned = false }
            }
            try? await Task.sleep(for: .seconds(IslandMotion.collapse))
            guard !Task.isCancelled, let self else { return }
            self.phase = .closed
            self.media = .idle
            self.hideWindow()
        }
    }

    // MARK: - Open / pulse

    private func ensureOpen(onLockScreen: Bool, style: UnlockAnimationStyle? = nil) {
        transitionTask?.cancel()
        // Re-measured on every open: right after wake AppKit may not have laid out the
        // menu bar yet, so a stale reading would mis-size the notch.
        geometry = NotchGeometry.current
        let fresh = phase == .closed
        if fresh {
            activeStyle = style ?? .saved
            isExpanded = false
            isPositioned = geometry.style == .notch
        }
        place(onLockScreen: onLockScreen)
        if fresh { window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }

        let isPill = geometry.style == .pill
        transitionTask = Task { [weak self] in
            // Let the closed frame render so the open animates from it, not from nothing.
            if fresh { try? await Task.sleep(for: .milliseconds(30)) }
            guard !Task.isCancelled, let self else { return }
            if isPill, !self.isPositioned {
                withAnimation(Self.slide) { self.isPositioned = true }
                try? await Task.sleep(for: .seconds(IslandMotion.pillEnterDelay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(Self.spring(IslandMotion.openSpring)) { self.isExpanded = true }
        }
    }

    /// Each half-cycle is its own finite `withAnimation` rather than one `repeatForever`:
    /// a repeatForever owns the property for its lifetime and snaps on removal, whereas
    /// discrete half-cycles let `stopPulse()` retarget mid-flight from the rendered value.
    private func startPulse() {
        guard pulseTask == nil else { return }
        let entry = (geometry.style == .pill ? IslandMotion.pillEnterDelay : 0)
            + IslandMotion.pulseStartDelay
        pulseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(entry))
            let half = IslandMotion.pulseHalfCycle
            while !Task.isCancelled {
                for dimmed in [true, false] {
                    withAnimation(.easeInOut(duration: half)) { self?.isPulseDimmed = dimmed }
                    try? await Task.sleep(for: .seconds(half + IslandMotion.pulseHold))
                    if Task.isCancelled { return }
                }
            }
        }
    }

    private func stopPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        guard isPulseDimmed else { return }
        withAnimation(.easeOut(duration: IslandMotion.pulseSettle)) { isPulseDimmed = false }
    }

    // MARK: - Window

    private static func spring(_ values: (response: Double, damping: Double)) -> Animation {
        .spring(response: values.response, dampingFraction: values.damping)
    }

    /// A straight-line move, not a bouncy resize.
    private static let slide = Animation.easeOut(duration: IslandMotion.pillSlide)

    private func place(onLockScreen: Bool) {
        reposition()
        window.orderFrontRegardless()
        if onLockScreen, !isOnLockScreen, let elevated {
            elevated.show(window)
            isOnLockScreen = true
        } else if !onLockScreen, isOnLockScreen, let elevated {
            elevated.hide(window)
            isOnLockScreen = false
        }
    }

    private func hideWindow() {
        if isOnLockScreen, let elevated { elevated.hide(window) }
        isOnLockScreen = false
        window.orderOut(nil)
        isLockOpen = false
    }

    private func reposition() {
        guard let screen = NotchGeometry.preferredScreen else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height))
    }

    /// Fixed size, created once and never resized — all growth is SwiftUI inside it.
    private func makeWindow() -> NSPanel {
        let size = IslandMetrics.windowSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the shadow is drawn in-content
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: NotchOverlayView(controller: self))
        return panel
    }
}
