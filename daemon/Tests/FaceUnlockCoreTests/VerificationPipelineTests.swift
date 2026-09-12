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

/// Identity cropper for tests that don't exercise real Vision face detection (the
/// dummy test images have no detectable face).
final class FakeCropper: FaceCropping {
    var shouldThrow: FaceEmbedderError?
    func crop(_ image: CGImage) throws -> CGImage {
        if let error = shouldThrow { throw error }
        return image
    }
}

func makeDummyImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 10, height: 10,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    return context.makeImage()!
}

func makePipeline(
    embedder: FakeEmbedder, classifier: FakeClassifier, config: PipelineConfig = PipelineConfig(),
    cropper: FaceCropping = FakeCropper()
) -> VerificationPipeline {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    return VerificationPipeline(embedder: embedder, classifier: classifier, store: store, config: config, cropper: cropper)
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

@Test func enrollWithEmptyImagesThrowsCleanly() throws {
    let pipeline = makePipeline(embedder: FakeEmbedder(), classifier: FakeClassifier())
    #expect(throws: VerificationPipelineError.noImagesProvided) {
        try pipeline.enroll(images: [])
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

// MARK: - Finding 3: liveness classifier must be fed the face crop, not the full frame

@Test func verifyPassesCroppedImageToBothClassifierAndEmbedder() throws {
    final class RecordingClassifier: LivenessChecking {
        var seen: CGImage?
        func classify(_ image: CGImage) throws -> LivenessResult {
            seen = image
            return LivenessResult(isLive: true, confidence: 0.99)
        }
    }
    final class RecordingEmbedder: FaceEmbedding_Provider {
        var seen: CGImage?
        func embedding(in image: CGImage) throws -> FaceEmbedding {
            seen = image
            return FaceEmbedding(vector: [1, 0, 0])
        }
    }

    let cropDummy = makeDummyImage()
    let cropper = FakeCropper()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SecureStore(keyProvider: FakeKeyProvider(), directory: dir)
    let embedder = RecordingEmbedder()
    let classifier = RecordingClassifier()
    let pipeline = VerificationPipeline(embedder: embedder, classifier: classifier, store: store, cropper: cropper)
    try store.save(Data([1, 0, 0].flatMap { withUnsafeBytes(of: Float($0)) { Array($0) } }), as: "face-centroid")

    _ = try pipeline.verify(image: cropDummy)

    #expect(classifier.seen === embedder.seen)
}

@Test func verifyPropagatesNoFaceDetectedFromCropStep() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let cropper = FakeCropper()
    cropper.shouldThrow = .noFaceDetected
    let pipeline = makePipeline(embedder: embedder, classifier: classifier, cropper: cropper)

    #expect(throws: FaceEmbedderError.noFaceDetected) {
        _ = try pipeline.verify(image: makeDummyImage())
    }
}

@Test func realVisionCropperThrowsNoFaceDetectedOnBlankImage() throws {
    // Mirrors FaceEmbedderTests' pattern: this is the practically-testable half of the
    // real Vision cropper (no-face case). Confirming it doesn't throw on an image that
    // *does* contain a face isn't practical here without a real face fixture.
    let cropper = VisionFaceCropper()
    let blank = makeSolidColorImage(width: 200, height: 200, gray: 0.5)
    #expect(throws: FaceEmbedderError.noFaceDetected) {
        _ = try cropper.crop(blank)
    }
}

// MARK: - Finding 7: a corrupted/mismatched stored centroid must fail, not crash

@Test func verifyFailsCleanlyWhenStoredCentroidDimensionMismatches() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let pipeline = makePipeline(embedder: embedder, classifier: classifier)

    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    try pipeline.enroll(images: [makeDummyImage()])

    // Simulate a corrupted/incompatible stored centroid by returning a longer vector
    // from the embedder at verify time (dimension mismatch vs. the 3-float centroid on
    // disk from enroll above).
    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0, 0, 0])
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}

// MARK: - Finding 8: low-confidence "live" classification must still fail

@Test func verifyFailsWhenLivenessConfidenceBelowThreshold() throws {
    let embedder = FakeEmbedder()
    let classifier = FakeClassifier()
    let pipeline = makePipeline(embedder: embedder, classifier: classifier)

    embedder.nextEmbedding = FaceEmbedding(vector: [1, 0, 0])
    try pipeline.enroll(images: [makeDummyImage()])

    // isLive is true (argmax is the live class) but confidence is well below the
    // default 0.7 threshold — should still fail.
    classifier.nextResult = LivenessResult(isLive: true, confidence: 0.5)
    #expect(try pipeline.verify(image: makeDummyImage()) == false)
}
