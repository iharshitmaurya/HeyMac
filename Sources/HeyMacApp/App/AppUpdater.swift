import AppKit
import Observation
import Sparkle

/// Checks for and installs new versions via Sparkle. The feed URL and the public key that
/// verifies each download live in Info.plist (`SUFeedURL`, `SUPublicEDKey`).
@MainActor @Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    /// False while a check is already running, so the buttons can disable themselves.
    private(set) var canCheck = false
    private(set) var checksAutomatically = true
    /// True once Sparkle has begun installing, so the quit it triggers isn't stopped by
    /// App Lock's quit prompt. Cleared if the update is abandoned.
    private(set) var isInstalling = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Starts the background update cycle. Skipped in the UI-render harness and in
    /// builds run outside an app bundle (`swift run`), where there is no feed to read.
    func start() {
        guard controller == nil, !AppModel.uiSnapshotMode,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheck = value }
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkNow() {
        controller?.checkForUpdates(nil)
    }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        checksAutomatically = on
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Task { @MainActor in self.isInstalling = true }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in self.isInstalling = false }
    }
}
