import Testing
import CoreGraphics
@testable import FaceUnlockCore

@Test func embedderLoadsWithoutThrowing() throws {
    _ = try FaceEmbedder()
}

@Test func noFaceInBlankImageThrowsNoFaceDetected() throws {
    let embedder = try FaceEmbedder()
    let blankImage = makeSolidColorImage(width: 200, height: 200, gray: 0.5)
    #expect(throws: FaceEmbedderError.noFaceDetected) {
        _ = try embedder.embedding(in: blankImage)
    }
}

func makeSolidColorImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: gray, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
