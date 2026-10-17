import Testing
import Foundation
@testable import HeyMacEngine

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

@Test func setupCanFinishWithoutEnrollingAFace() {
    let settings = EngineSettings(defaults: UserDefaults(suiteName: "setup-plan-\(UUID().uuidString)")!)
    #expect(!settings.onboardingComplete)
    settings.onboardingComplete = true
    #expect(settings.onboardingComplete)
    #expect(!settings.setupComplete)
    settings.resetAll()
    #expect(!settings.onboardingComplete)
}

@Test func existingEnrolledUsersHaveCompletedOnboarding() {
    let settings = makeTestSettings()
    #expect(settings.onboardingComplete)
    settings.onboardingComplete = true
    settings.setupComplete = false
    #expect(settings.onboardingComplete)
}
