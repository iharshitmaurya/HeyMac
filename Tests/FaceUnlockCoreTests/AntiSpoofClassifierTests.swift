import Testing
import CoreGraphics
@testable import FaceUnlockCore

@Test func classifierLoadsWithoutThrowing() throws {
    _ = try AntiSpoofClassifier()
}

@Test func flatGrayPatchIsNotLive() throws {
    let classifier = try AntiSpoofClassifier()
    let patch = RGBAImage(width: 80, height: 80, bytes: [UInt8](repeating: 128, count: 80 * 80 * 4))
    #expect(try classifier.classify(patch: patch).isLive == false)
}

@Test func modelOutputDependsOnInput() throws {
    // The 2026-09-12 conversion returned the same distribution for every input; this
    // catches that failure mode directly.
    let classifier = try AntiSpoofClassifier()
    let dark = try classifier.probabilities(for: RGBAImage(width: 80, height: 80, bytes: [UInt8](repeating: 10, count: 80 * 80 * 4)))
    let bright = try classifier.probabilities(for: RGBAImage(width: 80, height: 80, bytes: [UInt8](repeating: 240, count: 80 * 80 * 4)))
    let delta = zip(dark, bright).map { abs($0 - $1) }.max() ?? 0
    #expect(delta > 0.01)
}
