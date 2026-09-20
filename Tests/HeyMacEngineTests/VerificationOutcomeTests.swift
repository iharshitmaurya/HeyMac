import Testing
@testable import HeyMacEngine

@Test func failureSummaryNamesTheReason() {
    var outcome = VerificationOutcome()
    outcome.failure = "not enrolled"
    #expect(outcome.summary == "FAIL (not enrolled)")
}

@Test func matchSummaryReportsScores() {
    var outcome = VerificationOutcome()
    outcome.matched = true
    outcome.framesEvaluated = 2
    outcome.bestSimilarity = 0.9
    outcome.bestLiveness = 0.99
    #expect(outcome.summary == "OK frames=2 noFace=0 bestSimilarity=0.900 bestLiveness=0.990")
}
