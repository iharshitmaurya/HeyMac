import Vision
import CoreML
import CoreImage
import CoreVideo
import Foundation

public enum FaceEmbedderError: Error, Equatable {
    case noFaceDetected
    case modelLoadFailed
    case inferenceFailed
}

public final class FaceEmbedder: FaceEmbedding_Provider {
    private let model: MLModel
    private let inputName = "input_image"
    private let outputName = "embedding"
    private let inputSize = (width: 112, height: 112)

    public init() throws {
        guard let url = Bundle.module.url(forResource: "ArcFace", withExtension: "mlpkgdata") else {
            throw FaceEmbedderError.modelLoadFailed
        }
        do {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL)
        } catch {
            throw FaceEmbedderError.modelLoadFailed
        }
    }

    public func embedding(in image: CGImage) throws -> FaceEmbedding {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        try? handler.perform([request])
        guard let face = request.results?.first else {
            throw FaceEmbedderError.noFaceDetected
        }
        let pixelBuffer = try Self.alignedPixelBuffer(from: image, boundingBox: face.boundingBox, targetSize: inputSize)
        return try infer(on: pixelBuffer)
    }

    private func infer(on pixelBuffer: CVPixelBuffer) throws -> FaceEmbedding {
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let output = try? model.prediction(from: provider),
              let multiArray = output.featureValue(for: outputName)?.multiArrayValue
        else {
            throw FaceEmbedderError.inferenceFailed
        }
        var vector = [Float](repeating: 0, count: multiArray.count)
        for i in 0..<multiArray.count { vector[i] = multiArray[i].floatValue }
        return FaceEmbedding(vector: vector)
    }

    private static func alignedPixelBuffer(from image: CGImage, boundingBox: CGRect, targetSize: (width: Int, height: Int)) throws -> CVPixelBuffer {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        // Vision's normalized boundingBox has its origin at the bottom-left; CGImage's is top-left.
        let rect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        ).integral

        guard rect.width > 0, rect.height > 0, let cropped = image.cropping(to: rect) else {
            throw FaceEmbedderError.noFaceDetected
        }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, targetSize.width, targetSize.height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { throw FaceEmbedderError.inferenceFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: targetSize.width, height: targetSize.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            throw FaceEmbedderError.inferenceFailed
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
        return buffer
    }
}
