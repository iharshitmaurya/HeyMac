import Testing
import CoreGraphics
import Foundation
@testable import HeyMacCore

// Expected rects come from running upstream's CropImage._get_new_box on the same inputs.
@Test(arguments: [
    (CGRect(x: 442, y: 220, width: 475, height: 495), 1280, 720, 2.7, CGRect(x: 334, y: 0, width: 691, height: 720)),
    (CGRect(x: 106, y: 147, width: 207, height: 213), 480, 640, 2.7, CGRect(x: 0, y: 7, width: 480, height: 493)),
    (CGRect(x: 0, y: 0, width: 100, height: 100), 640, 480, 2.7, CGRect(x: 0, y: 0, width: 271, height: 271)),
    (CGRect(x: 600, y: 400, width: 100, height: 100), 640, 480, 2.7, CGRect(x: 369, y: 209, width: 271, height: 271)),
    (CGRect(x: 423, y: 238, width: 531, height: 531), 1280, 720, 2.4, CGRect(x: 329, y: 0, width: 720, height: 720)),
] as [(CGRect, Int, Int, CGFloat, CGRect)])
func antiSpoofCropMatchesUpstream(box: CGRect, width: Int, height: Int, scale: CGFloat, expected: CGRect) {
    #expect(FaceGeometry.antiSpoofCropRect(faceBox: box, imageWidth: width, imageHeight: height, scale: scale) == expected)
}

@Test func similarityTransformOfTemplateOntoItselfIsIdentity() {
    let t = FaceGeometry.similarityTransform(from: FaceGeometry.arcFaceTemplate, to: FaceGeometry.arcFaceTemplate)
    #expect(abs(t.a - 1) < 1e-9 && abs(t.b) < 1e-9 && abs(t.tx) < 1e-7 && abs(t.ty) < 1e-7)
}

@Test func similarityTransformRecoversRotationScaleAndTranslation() {
    let known = CGAffineTransform(rotationAngle: 0.3).scaledBy(x: 4.5, y: 4.5).translatedBy(x: 120, y: -40)
    let moved = FaceGeometry.arcFaceTemplate.map { $0.applying(known) }
    let recovered = FaceGeometry.similarityTransform(from: moved, to: FaceGeometry.arcFaceTemplate)
    for (point, original) in zip(moved, FaceGeometry.arcFaceTemplate) {
        let mapped = point.applying(recovered)
        #expect(abs(mapped.x - original.x) < 1e-6 && abs(mapped.y - original.y) < 1e-6)
    }
}

@Test func resizeOfUniformRegionKeepsColor() {
    var bytes = [UInt8](repeating: 0, count: 40 * 30 * 4)
    for i in stride(from: 0, to: bytes.count, by: 4) { bytes[i] = 200; bytes[i + 1] = 100; bytes[i + 2] = 50; bytes[i + 3] = 255 }
    let out = FaceGeometry.resize(RGBAImage(width: 40, height: 30, bytes: bytes), region: CGRect(x: 5, y: 5, width: 20, height: 20), width: 8, height: 8)
    #expect(out.bytes[0] == 200 && out.bytes[1] == 100 && out.bytes[2] == 50)
}

func fixtureImage(_ name: String) throws -> CGImage {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
    return try #require(loadOrientedImage(at: url))
}

/// End-to-end regression for the real models on upstream's labeled samples: Vision
/// detection → upstream crop → converted anti-spoof model must agree with upstream's
/// PyTorch verdicts (T1 real; F1, F2 spoof).
@Test(arguments: [("image_T1", true), ("image_F1", false), ("image_F2", false)])
func realPipelineLivenessMatchesUpstreamLabels(name: String, expectedLive: Bool) throws {
    let image = try fixtureImage(name)
    let frame = try #require(RGBAImage(cgImage: image))
    let face = try VisionFaceDetector().detectLargestFace(in: image)
    let result = try AntiSpoofClassifier().liveness(for: face, in: frame)
    #expect(result.isLive == expectedLive, "\(name): live probability \(result.confidence)")
}

@Test func alignedEmbeddingIsStableWhenFaceMovesInFrame() throws {
    let image = try fixtureImage("image_T1")
    // Same photo shrunk to 70% and placed off-center on a larger canvas: position and
    // scale change, identity doesn't.
    let canvasW = image.width + 200, canvasH = image.height + 120
    let context = try #require(CGContext(
        data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
    context.draw(image, in: CGRect(x: 170, y: 40, width: Double(image.width) * 0.7, height: Double(image.height) * 0.7))
    let moved = try #require(context.makeImage())

    let embedder = try FaceEmbedder()
    let a = try embedder.embedding(in: image)
    let b = try embedder.embedding(in: moved)
    #expect(EmbeddingMath.cosineSimilarity(a, b) > 0.8)
}
