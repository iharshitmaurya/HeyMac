import Testing
import Foundation
import CoreGraphics
@testable import FaceUnlockCore

let fakeFace = DetectedFace(
    boundingBox: CGRect(x: 2, y: 2, width: 6, height: 6),
    landmarks: [CGPoint(x: 3, y: 4), CGPoint(x: 7, y: 4), CGPoint(x: 5, y: 5), CGPoint(x: 4, y: 7), CGPoint(x: 6, y: 7)]
)

final class FakeDetector: FaceDetecting {
    var shouldThrow: FaceEmbedderError?
    func detectLargestFace(in image: CGImage) throws -> DetectedFace {
        if let error = shouldThrow { throw error }
        return fakeFace
    }
}

final class FakeEmbedder: FaceEmbedding_Provider {
    var nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    func embedding(for face: DetectedFace, in frame: RGBAImage) throws -> FaceEmbedding { nextEmbedding }
}

final class FakeClassifier: LivenessChecking {
    var nextResult = LivenessResult(isLive: true, confidence: 0.99)
    func liveness(for face: DetectedFace, in frame: RGBAImage) throws -> LivenessResult { nextResult }
}

func makeDummyImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}

func makePipeline(
    embedder: FakeEmbedder = FakeEmbedder(), classifier: FakeClassifier = FakeClassifier(),
    detector: FakeDetector = FakeDetector(), config: PipelineConfig = PipelineConfig()
) -> VerificationPipeline {
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: makeTempDirectory())
    return VerificationPipeline(detector: detector, embedder: embedder, classifier: classifier, store: store, config: config)
}

@Test func enrollThenVerifyWithSameFaceSucceeds() throws {
    let embedder = FakeEmbedder()
    let pipeline = makePipeline(embedder: embedder)
    try pipeline.enroll(images: [makeDummyImage(), makeDummyImage()])
    #expect(try pipeline.verify(image: makeDummyImage()) == true)
}

@Test func verifyWithDifferentFaceFails() throws {
    let embedder = FakeEmbedder()
    let pipeline = makePipeline(embedder: embedder)
    try pipeline.enroll(images: [makeDummyImage()])
    embedder.nextEmbedding = FaceEmbedding(vector: [0, 1, 0])
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

@Test func verifyFailsWhenLivenessCheckFails() throws {
    let classifier = FakeClassifier()
    let pipeline = makePipeline(classifier: classifier)
    try pipeline.enroll(images: [makeDummyImage()])
    classifier.nextResult = LivenessResult(isLive: false, confidence: 0.1)
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

@Test func verifyFailsWhenLivenessConfidenceBelowThreshold() throws {
    let classifier = FakeClassifier()
    let pipeline = makePipeline(classifier: classifier)
    try pipeline.enroll(images: [makeDummyImage()])
    classifier.nextResult = LivenessResult(isLive: true, confidence: 0.5)
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

@Test func enrollmentRejectsFramesThatFailLiveness() throws {
    let classifier = FakeClassifier()
    classifier.nextResult = LivenessResult(isLive: false, confidence: 0.02)
    let pipeline = makePipeline(classifier: classifier)
    #expect(throws: VerificationPipelineError.notLive(confidence: 0.02)) {
        _ = try pipeline.enrollmentSample(from: makeDummyImage())
    }
}

@Test func verifyBeforeEnrollmentThrows() throws {
    #expect(throws: SecureStoreError.notFound) {
        _ = try makePipeline().verify(image: makeDummyImage())
    }
}

@Test func enrollWithEmptyImagesThrowsCleanly() throws {
    #expect(throws: VerificationPipelineError.noImagesProvided) {
        try makePipeline().enroll(images: [])
    }
}

@Test func noFaceDetectedPropagates() throws {
    let detector = FakeDetector()
    detector.shouldThrow = .noFaceDetected
    let pipeline = makePipeline(detector: detector)
    #expect(throws: FaceEmbedderError.noFaceDetected) {
        try pipeline.enroll(images: [makeDummyImage()])
    }
}

@Test func enrolledCentroidIsUnitLength() throws {
    let embedder = FakeEmbedder()
    embedder.nextEmbedding = FaceEmbedding(vector: [3, 4, 0])
    let pipeline = makePipeline(embedder: embedder)
    try pipeline.enroll(images: [makeDummyImage()])
    let centroid = try pipeline.loadEnrolledCentroid()
    #expect(abs(centroid.vector.reduce(0) { $0 + $1 * $1 } - 1) < 1e-5)
}

@Test func verifyFailsCleanlyWhenStoredCentroidDimensionMismatches() throws {
    let embedder = FakeEmbedder()
    let pipeline = makePipeline(embedder: embedder)
    try pipeline.enroll(images: [makeDummyImage()])
    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0, 0, 0])
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}
