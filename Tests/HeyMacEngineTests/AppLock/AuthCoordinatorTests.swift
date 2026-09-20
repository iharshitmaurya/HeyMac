import Testing
import Foundation
@testable import HeyMacEngine

private final class FakeFace: FaceAuthSource, @unchecked Sendable {
    var result: FaceAuthResult
    private(set) var calls = 0
    init(_ result: FaceAuthResult) { self.result = result }
    func authenticate(timeout: TimeInterval) async -> FaceAuthResult { calls += 1; return result }
}

private final class FakeSystem: SystemAuthSource, @unchecked Sendable {
    var result: SystemAuthResult
    private(set) var calls = 0
    init(_ result: SystemAuthResult) { self.result = result }
    func authenticate(reason: String) async -> SystemAuthResult { calls += 1; return result }
}

@Test func faceMatchUnlocksWithoutTouchingSystemAuth() async {
    let face = FakeFace(.matched), system = FakeSystem(.success)
    let outcome = await AuthCoordinator(face: face, system: system).run(reason: "Unlock Notes")
    #expect(outcome == .unlocked(.face))
    #expect(system.calls == 0)
}

@Test func faceMissFallsBackToSystemAuth() async {
    for miss in [FaceAuthResult.noMatch, .unavailable] {
        let face = FakeFace(miss), system = FakeSystem(.success)
        let outcome = await AuthCoordinator(face: face, system: system).run(reason: "x")
        #expect(outcome == .unlocked(.system))
        #expect(system.calls == 1)
    }
}

@Test func noFaceSourceGoesStraightToSystemAuth() async {
    let system = FakeSystem(.success)
    let outcome = await AuthCoordinator(face: nil, system: system).run(reason: "x")
    #expect(outcome == .unlocked(.system))
}

@Test func systemCancelAndFailureAreReported() async {
    let cancelled = await AuthCoordinator(face: nil, system: FakeSystem(.cancelled)).run(reason: "x")
    #expect(cancelled == .cancelled)
    let denied = await AuthCoordinator(face: nil, system: FakeSystem(.failed("Wrong password"))).run(reason: "x")
    #expect(denied == .denied("Wrong password"))
}

@Test func cancelledTaskNeverReachesSystemAuth() async {
    let face = FakeFace(.noMatch), system = FakeSystem(.success)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await AuthCoordinator(face: face, system: system).run(reason: "x")
    }
    #expect(await task.value == .cancelled)
    #expect(system.calls == 0)
}

@Test func verificationOutcomesAreClassified() {
    var matched = VerificationOutcome(); matched.matched = true
    #expect(FaceVerifierAuthSource.classify(matched) == .matched)
    #expect(FaceVerifierAuthSource.classify(VerificationOutcome()) == .noMatch) // timed out, no failure text
    var notEnrolled = VerificationOutcome(); notEnrolled.failure = "not enrolled"
    #expect(FaceVerifierAuthSource.classify(notEnrolled) == .unavailable)
    var busy = VerificationOutcome(); busy.failure = "camera busy with another verification"
    #expect(FaceVerifierAuthSource.classify(busy) == .unavailable)
}

@Test func faceSourceRunsTheMatcher() async {
    let matcher = FakeMatcher()
    matcher.outcome = matchedOutcome()
    let result = await FaceVerifierAuthSource(matcher: matcher).authenticate(timeout: 1)
    #expect(result == .matched)
    #expect(matcher.callCount == 1)
}
