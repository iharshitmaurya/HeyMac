import Foundation
import CoreGraphics
import Vision

public protocol FaceEmbedding_Provider {
    func embedding(in image: CGImage) throws -> FaceEmbedding
}

public protocol LivenessChecking {
    func classify(_ image: CGImage) throws -> LivenessResult
}

/// Detects and crops the face region from a frame, so the same face-region image (not
/// the full, mostly-background frame) can be handed to both the embedder and the
/// liveness classifier.
public protocol FaceCropping {
    func crop(_ image: CGImage) throws -> CGImage
}

/// Vision-based cropper, using the same face-detection approach `FaceEmbedder` uses
/// internally. Returns a `CGImage` (rather than a `CVPixelBuffer`) since the crop needs
/// to be handed to two different consumers (embedder, classifier).
public struct VisionFaceCropper: FaceCropping {
    public init() {}

    public func crop(_ image: CGImage) throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        try? handler.perform([request])
        guard let face = request.results?.first else {
            throw FaceEmbedderError.noFaceDetected
        }
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        // Vision's normalized boundingBox has its origin at the bottom-left; CGImage's is top-left.
        let rect = CGRect(
            x: face.boundingBox.origin.x * imageWidth,
            y: (1 - face.boundingBox.origin.y - face.boundingBox.height) * imageHeight,
            width: face.boundingBox.width * imageWidth,
            height: face.boundingBox.height * imageHeight
        ).integral
        guard rect.width > 0, rect.height > 0, let cropped = image.cropping(to: rect) else {
            throw FaceEmbedderError.noFaceDetected
        }
        return cropped
    }
}

public enum VerificationPipelineError: Error, Equatable {
    case noImagesProvided
}

public struct PipelineConfig {
    public let matchThreshold: Float
    /// Minimum confidence the anti-spoof classifier must have in its "live" prediction,
    /// on top of "live" actually being the argmax class. The spec requires "low
    /// confidence" liveness to fail verification, not just a wrong top class. 0.7 is a
    /// conservative floor given real observed outputs are decisive (e.g. [0.0003,
    /// 0.0054, 0.9941] for a confident non-live read) — a "live" call anywhere near the
    /// decision boundary should not be trusted.
    public let livenessThreshold: Float
    public init(matchThreshold: Float = 0.42, livenessThreshold: Float = 0.7) {
        self.matchThreshold = matchThreshold
        self.livenessThreshold = livenessThreshold
    }
}

public final class VerificationPipeline {
    private let embedder: FaceEmbedding_Provider
    private let classifier: LivenessChecking
    private let store: SecureStore
    private let config: PipelineConfig
    private let cropper: FaceCropping
    private let centroidKey = "face-centroid"

    public init(
        embedder: FaceEmbedding_Provider, classifier: LivenessChecking, store: SecureStore,
        config: PipelineConfig = PipelineConfig(), cropper: FaceCropping = VisionFaceCropper()
    ) {
        self.embedder = embedder
        self.classifier = classifier
        self.store = store
        self.config = config
        self.cropper = cropper
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
        let faceCrop = try cropper.crop(image)

        let liveness = try classifier.classify(faceCrop)
        guard liveness.isLive, liveness.confidence >= config.livenessThreshold else { return false }

        let stored = try store.load(centroidKey)
        let candidate = try embedder.embedding(in: faceCrop)

        // The stored centroid comes from disk and could be corrupted, truncated, or
        // written by an incompatible build. EmbeddingMath.cosineSimilarity uses
        // `precondition` on dimension match, which would crash the process (and can't
        // be caught by `try?`), defeating the fail-safe design. Validate here, the one
        // place that receives externally-sourced data, before calling into it.
        guard stored.count == candidate.vector.count * MemoryLayout<Float>.size else { return false }

        let centroid = stored.withUnsafeBytes { rawBuffer -> FaceEmbedding in
            let floats = rawBuffer.bindMemory(to: Float.self)
            return FaceEmbedding(vector: Array(floats))
        }
        let similarity = EmbeddingMath.cosineSimilarity(centroid, candidate)
        return similarity >= config.matchThreshold
    }
}
