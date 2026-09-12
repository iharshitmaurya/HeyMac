import Testing
import Foundation
import CoreGraphics
@testable import FaceUnlockCore

final class FakeEmbedder: FaceEmbedding_Provider {
    var nextEmbedding: FaceEmbedding = FaceEmbedding(vector: [1, 0, 0])
    var shouldThrow: FaceEmbedderError?
    func embedding(in image: CGImage) throws -> FaceEmbedding {
        if let error = shouldThrow { throw error }
        return nextEmbedding
    }
}

final class FakeClassifier: LivenessChecking {
    var nextResult = LivenessResult(isLive: true, confidence: 0.99)
    func classify(_ image: CGImage) throws -> LivenessResult { nextResult }
}

func makeDummyImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 10, height: 10,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}

func makePipeline(embedder: FakeEmbedder, classifier: FakeClassifier) -> VerificationPipeline {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    return VerificationPipeline(embedder: embedder, classifier: classifier, store: store)
}

@Test func enrollThenVerifyWithSameFaceSucceeds() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let pipeline = makePipeline(embedder: embedder, classifier: classifier)

    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    try pipeline.enroll(images: [makeDummyImage(), makeDummyImage()])

    #expect(try pipeline.verify(image: makeDummyImage()) == true)
}

@Test func verifyWithDifferentFaceFails() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let pipeline = makePipeline(embedder: embedder, classifier: classifier)

    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    try pipeline.enroll(images: [makeDummyImage()])

    embedder.nextEmbedding = FaceEmbedding(vector: [0, 1, 0])
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

@Test func verifyFailsWhenLivenessCheckFails() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let pipeline = makePipeline(embedder: embedder, classifier: classifier)

    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    try pipeline.enroll(images: [makeDummyImage()])

    classifier.nextResult = LivenessResult(isLive: false, confidence: 0.1)
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

@Test func verifyBeforeEnrollmentThrows() throws {
    let pipeline = makePipeline(embedder: FakeEmbedder(), classifier: FakeClassifier())
    #expect(throws: SecureStoreError.notFound) {
        _ = try pipeline.verify(image: makeDummyImage())
    }
}

@Test func enrollWithNoFaceDetectedPropagatesError() throws {
    let embedder = FakeEmbedder()
    embedder.shouldThrow = .noFaceDetected
    let pipeline = makePipeline(embedder: embedder, classifier: FakeClassifier())
    #expect(throws: FaceEmbedderError.noFaceDetected) {
        try pipeline.enroll(images: [makeDummyImage()])
    }
}
