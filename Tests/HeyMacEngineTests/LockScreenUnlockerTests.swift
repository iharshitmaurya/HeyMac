import Testing
import Foundation
import HeyMacCore
@testable import HeyMacEngine

private func makeUnlocker(
    system: FakeSystem, matcher: FakeMatcher, typist: PasswordTyping, settings: EngineSettings, recorder: EventRecorder
) -> LockScreenUnlocker {
    LockScreenUnlocker(
        matcher: matcher, typist: typist, settings: settings,
        environment: system.environment(), onEvent: { recorder.record($0) }
    )
}

@Test func typesThePasswordWhenTheFaceMatches() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let typist = FakeTypist(system: system, unlocks: true)
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: typist, settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .unlocked)
    #expect(typist.typed == ["hunter2"])
    #expect(recorder.events == [.lockScreenScanning, .lockScreenUnlocked(summary: matchedOutcome().summary)])
    #expect(settings.lockScreenNeedsPassword == false)
}

@Test func aRejectedPasswordStopsFurtherTyping() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let typist = FakeTypist(system: system, unlocks: false)
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: typist, settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .passwordRejected)
    #expect(settings.lockScreenNeedsPassword == true)
    #expect(recorder.events == [.lockScreenScanning, .lockScreenPasswordRejected])

    // Same lock episode: no second attempt.
    #expect(unlocker.tick() == .alreadyAttempted)
    // A new lock episode still refuses, because the stored password is known bad.
    system.locked = false
    #expect(unlocker.tick() == .notLocked)
    system.locked = true
    #expect(unlocker.tick() == .blocked(VerificationGate.passwordRejected))
    #expect(typist.typed.count == 1)
}

@Test func pausedNeverTouchesTheCamera() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let typist = FakeTypist(system: system, unlocks: true)
    let settings = makeTestSettings {
        $0.lockScreenEnabled = true
        $0.paused = true
    }
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: typist, settings: settings, recorder: EventRecorder())

    #expect(unlocker.tick() == .blocked("paused"))
    #expect(matcher.callCount == 0)
    #expect(typist.typed.isEmpty)
}

@Test func missingAccessibilityIsReportedOnce() {
    let system = FakeSystem()
    system.accessibilityTrusted = false
    let matcher = FakeMatcher()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .blocked(VerificationGate.accessibilityMissing))
    #expect(unlocker.tick() == .blocked(VerificationGate.accessibilityMissing))
    #expect(recorder.events == [.lockScreenProblem(VerificationGate.accessibilityMissing)])
    #expect(matcher.callCount == 0)
}

@Test func aSleepingDisplayKeepsTheCameraOff() {
    let system = FakeSystem()
    system.displayAwake = false
    let matcher = FakeMatcher()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: EventRecorder())

    #expect(unlocker.tick() == .displayAsleep)
    #expect(matcher.callCount == 0)
}

@Test func anUnknownLockStateNeverTypes() {
    let system = FakeSystem()
    system.locked = nil
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let typist = FakeTypist(system: system, unlocks: true)
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: typist, settings: settings, recorder: EventRecorder())

    #expect(unlocker.tick() == .notLocked)
    #expect(typist.typed.isEmpty)
}

private struct ThrowingTypist: PasswordTyping {
    struct Failure: Error {}
    func typeAndReturn(_ text: String) throws { throw Failure() }
}

@Test func aScanWithNoFaceClosesQuietly() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .noMatch)
    #expect(recorder.events == [.lockScreenScanning, .lockScreenNoFace(details: matcher.outcome.debugSummary)])
    #expect(system.slept.reduce(0, +) >= LockScreenUnlocker.noFaceCooldown)
}

@Test func aWrongFaceShowsTheFailure() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome.mismatched = true
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .noMatch)
    #expect(recorder.events == [.lockScreenScanning, .lockScreenNoMatch(details: matcher.outcome.debugSummary)])
    #expect(system.slept.reduce(0, +) >= LockScreenUnlocker.noMatchCooldown)
}

@Test func scanningStopsAfterOneRetryPerLock() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .noMatch)
    #expect(unlocker.tick() == .noMatch)
    #expect(unlocker.tick() == .retriesExhausted)
    #expect(matcher.callCount == 2)

    system.locked = false
    #expect(unlocker.tick() == .notLocked)
    system.locked = true
    #expect(unlocker.tick() == .noMatch)
    #expect(matcher.callCount == 3)
}

@Test func aScanCutShortByAnUnlockJustClosesTheIndicator() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.onRun = { system.locked = false }  // unlocked another way while scanning
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .noMatch)
    #expect(recorder.events == [.lockScreenScanning, .lockScreenScanEnded])
}

@Test func aSuccessfulUnlockDoesNotEmitScanEnded() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: FakeTypist(system: system, unlocks: true), settings: settings, recorder: recorder)

    #expect(unlocker.tick() == .unlocked)
    #expect(!recorder.events.contains(.lockScreenScanEnded))
}

@Test func aTypingFailureClosesTheIndicator() {
    let system = FakeSystem()
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let settings = makeTestSettings { $0.lockScreenEnabled = true }
    let recorder = EventRecorder()
    let unlocker = makeUnlocker(system: system, matcher: matcher, typist: ThrowingTypist(), settings: settings, recorder: recorder)

    guard case .typingFailed = unlocker.tick() else { Issue.record("expected .typingFailed"); return }
    #expect(recorder.events == [.lockScreenScanning, .lockScreenScanEnded])
}
