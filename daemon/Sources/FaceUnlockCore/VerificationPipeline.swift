import Foundation
import CoreGraphics

public protocol FaceEmbedding_Provider {
    func embedding(in image: CGImage) throws -> FaceEmbedding
}

public protocol LivenessChecking {
    func classify(_ image: CGImage) throws -> LivenessResult
}

public enum VerificationPipelineError: Error, Equatable {
    case noImagesProvided
}

public struct PipelineConfig {
    public let matchThreshold: Float
    public init(matchThreshold: Float = 0.42) {
        self.matchThreshold = matchThreshold
    }
}

public final class VerificationPipeline {
    private let embedder: FaceEmbedding_Provider
    private let classifier: LivenessChecking
    private let store: SecureStore
    private let config: PipelineConfig
    private let centroidKey = "face-centroid"

    public init(embedder: FaceEmbedding_Provider, classifier: LivenessChecking, store: SecureStore, config: PipelineConfig = PipelineConfig()) {
        self.embedder = embedder
        self.classifier = classifier
        self.store = store
        self.config = config
    }

    public func enroll(images: [CGImage]) throws {
        guard !images.isEmpty else { throw VerificationPipelineError.noImagesProvided }
        var embeddings: [FaceEmbedding] = []
        for image in images {
            embeddings.append(try embedder.embedding(in: image))
        }
        let centroid = EmbeddingMath.centroid(of: embeddings)
        let data = centroid.vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try store.save(data, as: centroidKey)
    }

    public func verify(image: CGImage) throws -> Bool {
        let liveness = try classifier.classify(image)
        guard liveness.isLive else { return false }

        let stored = try store.load(centroidKey)
        let centroid = stored.withUnsafeBytes { rawBuffer -> FaceEmbedding in
            let floats = rawBuffer.bindMemory(to: Float.self)
            return FaceEmbedding(vector: Array(floats))
        }
        let candidate = try embedder.embedding(in: image)
        let similarity = EmbeddingMath.cosineSimilarity(centroid, candidate)
        return similarity >= config.matchThreshold
    }
}
