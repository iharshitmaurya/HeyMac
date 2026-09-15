import CoreGraphics
import CoreML
import Foundation

public enum AntiSpoofError: Error, Equatable {
    case modelLoadFailed
    case inferenceFailed
}

public struct LivenessResult: Equatable, Sendable {
    public let isLive: Bool
    public let confidence: Float

    public init(isLive: Bool, confidence: Float) {
        self.isLive = isLive
        self.confidence = confidence
    }
}

public protocol LivenessChecking {
    func liveness(for face: DetectedFace, in frame: RGBAImage) throws -> LivenessResult
}

/// MiniFASNetV2 (2.7_80x80) from minivision-ai/Silent-Face-Anti-Spoofing. Input preparation
/// mirrors upstream test.py exactly: grow the detector box 2.7x (clamped/shifted into the
/// frame), cv2-style bilinear resize to 80x80, BGR raw 0-255 (the BGR order and lack of
/// scaling are baked into the converted model — see AntiSpoof.LICENSE.txt).
public final class AntiSpoofClassifier: LivenessChecking {
    /// Upstream's 2.7 is relative to its RetinaFace box; Vision's face box measured ~12%
    /// larger on the same webcam frame (531 vs 475 px), so 2.7 × 475/531 ≈ 2.4 frames the
    /// same region. Checked against the PyTorch reference: live stays ≥0.99 on both a
    /// close and a simulated far face with this value.
    public static let visionBoxScale: CGFloat = 2.4
    /// Upstream test.py: `if label == 1: Real Face`.
    static let liveClassIndex = 1
    static let inputSize = 80

    private let model: MLModel
    private let inputName = "input_image"
    private let outputName = "probabilities"

    public init() throws {
        guard let url = ModelResources.url(named: "AntiSpoof") else {
            throw AntiSpoofError.modelLoadFailed
        }
        do {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } catch {
            throw AntiSpoofError.modelLoadFailed
        }
    }

    public func liveness(for face: DetectedFace, in frame: RGBAImage) throws -> LivenessResult {
        let region = FaceGeometry.antiSpoofCropRect(
            faceBox: face.boundingBox, imageWidth: frame.width, imageHeight: frame.height, scale: Self.visionBoxScale
        )
        return try classify(patch: FaceGeometry.resize(frame, region: region, width: Self.inputSize, height: Self.inputSize))
    }

    /// Classifies an already-prepared 80x80 patch.
    public func classify(patch: RGBAImage) throws -> LivenessResult {
        let probabilities = try probabilities(for: patch)
        let predicted = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] })!
        return LivenessResult(isLive: predicted == Self.liveClassIndex, confidence: probabilities[Self.liveClassIndex])
    }

    func probabilities(for patch: RGBAImage) throws -> [Float] {
        guard patch.width == Self.inputSize, patch.height == Self.inputSize,
              let pixelBuffer = patch.makePixelBuffer(),
              let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let output = try? model.prediction(from: provider),
              let multiArray = output.featureValue(for: outputName)?.multiArrayValue,
              multiArray.count == 3
        else {
            throw AntiSpoofError.inferenceFailed
        }
        return (0..<3).map { multiArray[$0].floatValue }
    }
}
