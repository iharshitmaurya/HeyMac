import CoreGraphics
import CoreML
import Foundation

public enum FaceEmbedderError: Error, Equatable {
    case noFaceDetected
    case modelLoadFailed
    case inferenceFailed
}

public protocol FaceEmbedding_Provider {
    func embedding(for face: DetectedFace, in frame: RGBAImage) throws -> FaceEmbedding
}

/// ArcFace (w600k_mbf). The model's input spec is "112x112 RGB aligned face crop" with
/// (x - 127.5) / 127.5 normalization baked in, so the only preprocessing owed here is the
/// 5-landmark similarity alignment — without it the model compares framing, not identity.
public final class FaceEmbedder: FaceEmbedding_Provider {
    private let model: MLModel
    private let inputName = "input_image"
    private let outputName = "embedding"

    public init() throws {
        guard let url = ModelResources.url(named: "ArcFace") else {
            throw FaceEmbedderError.modelLoadFailed
        }
        do {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } catch {
            throw FaceEmbedderError.modelLoadFailed
        }
    }

    public func embedding(for face: DetectedFace, in frame: RGBAImage) throws -> FaceEmbedding {
        guard face.landmarks.count == 5 else { throw FaceEmbedderError.noFaceDetected }
        let aligned = FaceGeometry.alignedFace(in: frame, landmarks: face.landmarks)
        guard let pixelBuffer = aligned.makePixelBuffer(),
              let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let output = try? model.prediction(from: provider),
              let multiArray = output.featureValue(for: outputName)?.multiArrayValue
        else {
            throw FaceEmbedderError.inferenceFailed
        }
        var vector = [Float](repeating: 0, count: multiArray.count)
        for i in 0..<multiArray.count { vector[i] = multiArray[i].floatValue }
        return EmbeddingMath.normalized(FaceEmbedding(vector: vector))
    }

    /// Detect-then-embed convenience for callers holding just a frame.
    public func embedding(in image: CGImage, detector: FaceDetecting = VisionFaceDetector()) throws -> FaceEmbedding {
        let face = try detector.detectLargestFace(in: image)
        guard let frame = RGBAImage(cgImage: image) else { throw FaceEmbedderError.inferenceFailed }
        return try embedding(for: face, in: frame)
    }
}
