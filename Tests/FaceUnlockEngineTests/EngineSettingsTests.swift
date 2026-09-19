import Testing
import Foundation
@testable import FaceUnlockEngine

@Test func settingsRoundTripAndResetToDefaults() {
    let settings = makeTestSettings()
    #expect(settings.strictness == .normal)
    #expect(settings.launchAtLogin == true)

    settings.lockScreenEnabled = true
    settings.strictness = .strict
    settings.launchAtLogin = false
    #expect(settings.strictness.threshold == 0.6)

    settings.resetAll()
    #expect(settings.setupComplete == false)
    #expect(settings.lockScreenEnabled == false)
    #expect(settings.strictness == .normal)
    #expect(settings.launchAtLogin == true)
}

@Test func strictnessThresholdsAreOrdered() {
    #expect(MatchStrictness.relaxed.threshold < MatchStrictness.normal.threshold)
    #expect(MatchStrictness.normal.threshold < MatchStrictness.strict.threshold)
}

@Test func lockScreenNeedsPermissionAndAGoodPassword() {
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    #expect(VerificationGate.lockScreen(settings, accessibilityTrusted: true) == .allow)
    #expect(VerificationGate.lockScreen(settings, accessibilityTrusted: false) == .refuse(VerificationGate.accessibilityMissing))

    settings.lockScreenNeedsPassword = true
    #expect(VerificationGate.lockScreen(settings, accessibilityTrusted: true) == .refuse(VerificationGate.passwordRejected))
}
