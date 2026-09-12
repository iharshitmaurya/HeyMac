import Testing
import CoreGraphics
@testable import FaceUnlockCore

@Test func classifierLoadsWithoutThrowing() throws {
    _ = try AntiSpoofClassifier()
}

@Test func flatColorImageClassifiesAsNotLive() throws {
    // Verified during planning: a flat gray 80x80 input yields a confident non-live
    // classification from this model (spoof classes dominate for a textureless input).
    let classifier = try AntiSpoofClassifier()
    let flatImage = makeSolidColorImage(width: 80, height: 80, gray: 0.5)
    let result = try classifier.classify(flatImage)
    #expect(result.isLive == false)
}
