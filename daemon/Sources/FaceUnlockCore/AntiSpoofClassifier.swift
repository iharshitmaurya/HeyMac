import CoreML
import CoreGraphics
import CoreVideo
import Foundation

public enum AntiSpoofError: Error, Equatable {
    case modelLoadFailed
    case inferenceFailed
}

public struct LivenessResult: Equatable {
    public let isLive: Bool
    public let confidence: Float
}

public final class AntiSpoofClassifier {
    private let model: MLModel
    private let inputName = "input_image"
    private let outputName = "probabilities"
    private let inputSize = (width: 80, height: 80)
    /// Per minivision-ai/Silent-Face-Anti-Spoofing's own test.py: index 1 is "real face".
    private let liveClassIndex = 1

    public init() throws {
        guard let url = Bundle.module.url(forResource: "AntiSpoof", withExtension: "mlpkgdata") else {
            throw AntiSpoofError.modelLoadFailed
        }
        do {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } catch {
            throw AntiSpoofError.modelLoadFailed
        }
    }

    public func classify(_ image: CGImage) throws -> LivenessResult {
        let pixelBuffer = try Self.pixelBuffer(from: image, size: inputSize)
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let output = try? model.prediction(from: provider),
              let multiArray = output.featureValue(for: outputName)?.multiArrayValue,
              multiArray.count == 3
        else {
            throw AntiSpoofError.inferenceFailed
        }
        var probabilities = [Float](repeating: 0, count: 3)
        for i in 0..<3 { probabilities[i] = multiArray[i].floatValue }
        let liveConfidence = probabilities[liveClassIndex]
        let predictedIndex = probabilities.indices.max(by: { probabilities[$0] < probabilities[$1] })!
        return LivenessResult(isLive: predictedIndex == liveClassIndex, confidence: liveConfidence)
    }

    private static func pixelBuffer(from image: CGImage, size: (width: Int, height: Int)) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { throw AntiSpoofError.inferenceFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size.width, height: size.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw AntiSpoofError.inferenceFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return buffer
    }
}
