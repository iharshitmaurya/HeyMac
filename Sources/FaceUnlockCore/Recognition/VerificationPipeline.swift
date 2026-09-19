import CoreGraphics
import Foundation

public enum VerificationPipelineError: Error, Equatable {
    case noImagesProvided
    case notLive(confidence: Float)
    case corruptEnrollment
}

public struct PipelineConfig {
    /// Cosine similarity between a frame's L2-normalized aligned ArcFace embedding and the
    /// enrolled (normalized) centroid. Aligned w600k_mbf scores the same person well above
    /// 0.5 and different people well below 0.3; ohmylock ships 0.62 for the same model.
    public let matchThreshold: Float
    /// Minimum anti-spoof probability for the live class, on top of live being the argmax.
    /// Real webcam faces score ~0.99; upstream's print/replay samples score ≤0.002.
    public let livenessThreshold: Float

    public init(matchThreshold: Float = 0.5, livenessThreshold: Float = 0.6) {
        self.matchThreshold = matchThreshold
        self.livenessThreshold = livenessThreshold
    }
}

public struct FrameEvaluation: Equatable, Sendable {
    public let liveness: Float
    public let similarity: Float
    public let isLive: Bool
    public let isMatch: Bool

    public var accepted: Bool { isLive && isMatch }
}

public final class VerificationPipeline {
    private let detector: FaceDetecting
    private let embedder: FaceEmbedding_Provider
    private let classifier: LivenessChecking
    private let store: SecureStore
    public let config: PipelineConfig
    static let centroidKey = "face-centroid"

    public init(
        detector: FaceDetecting = VisionFaceDetector(), embedder: FaceEmbedding_Provider, classifier: LivenessChecking,
        store: SecureStore, config: PipelineConfig = PipelineConfig()
    ) {
        self.detector = detector
        self.embedder = embedder
        self.classifier = classifier
        self.store = store
        self.config = config
    }

    /// One enrollment sample: the frame must contain a face that passes liveness, so a
    /// photo can't be enrolled.
    public func enrollmentSample(from image: CGImage) throws -> (embedding: FaceEmbedding, liveness: LivenessResult) {
        let (face, frame) = try detect(in: image)
        let liveness = try classifier.liveness(for: face, in: frame)
        guard isLive(liveness) else { throw VerificationPipelineError.notLive(confidence: liveness.confidence) }
        return (try embedder.embedding(for: face, in: frame), liveness)
    }

    /// Saves the normalized centroid of `embeddings` as the enrolled identity.
    @discardableResult
    public func saveEnrollment(_ embeddings: [FaceEmbedding]) throws -> FaceEmbedding {
        guard !embeddings.isEmpty else { throw VerificationPipelineError.noImagesProvided }
        let centroid = EmbeddingMath.normalized(EmbeddingMath.centroid(of: embeddings.map(EmbeddingMath.normalized)))
        let data = centroid.vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try store.save(data, as: Self.centroidKey)
        return centroid
    }

    public func enroll(images: [CGImage]) throws {
        guard !images.isEmpty else { throw VerificationPipelineError.noImagesProvided }
        try saveEnrollment(images.map { try enrollmentSample(from: $0).embedding })
    }

    public func loadEnrolledCentroid() throws -> FaceEmbedding {
        let stored = try store.load(Self.centroidKey)
        guard !stored.isEmpty, stored.count % MemoryLayout<Float>.size == 0 else {
            throw VerificationPipelineError.corruptEnrollment
        }
        return stored.withUnsafeBytes { FaceEmbedding(vector: Array($0.bindMemory(to: Float.self))) }
    }

    public func evaluate(image: CGImage, against centroid: FaceEmbedding) throws -> FrameEvaluation {
        let (face, frame) = try detect(in: image)
        let liveness = try classifier.liveness(for: face, in: frame)
        let candidate = try embedder.embedding(for: face, in: frame)
        // The centroid comes from disk; a dimension mismatch (corrupt file, other build)
        // must fail closed rather than trip cosineSimilarity's precondition.
        let similarity = candidate.vector.count == centroid.vector.count ? EmbeddingMath.cosineSimilarity(centroid, candidate) : -1
        return FrameEvaluation(
            liveness: liveness.confidence, similarity: similarity,
            isLive: isLive(liveness), isMatch: similarity >= config.matchThreshold
        )
    }

    public func verify(image: CGImage) throws -> Bool {
        try evaluate(image: image, against: loadEnrolledCentroid()).accepted
    }

    private func isLive(_ result: LivenessResult) -> Bool {
        result.isLive && result.confidence >= config.livenessThreshold
    }

    private func detect(in image: CGImage) throws -> (DetectedFace, RGBAImage) {
        let face = try detector.detectLargestFace(in: image)
        guard let frame = RGBAImage(cgImage: image) else { throw FaceEmbedderError.inferenceFailed }
        return (face, frame)
    }
}
