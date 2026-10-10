import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// A face found in a frame, in pixel coordinates with a top-left origin (y grows down).
public struct DetectedFace: Equatable, Sendable {
    public let boundingBox: CGRect
    /// ArcFace alignment landmarks, in template order: image-left eye, image-right eye,
    /// nose tip, image-left mouth corner, image-right mouth corner.
    public let landmarks: [CGPoint]

    public init(boundingBox: CGRect, landmarks: [CGPoint]) {
        self.boundingBox = boundingBox
        self.landmarks = landmarks
    }
}

public protocol FaceDetecting {
    func detectLargestFace(in image: CGImage) throws -> DetectedFace
}

/// An 8-bit RGBA pixel buffer, top row first. Every model input is resampled from this,
/// so both models see pixels produced by the same bilinear sampler the upstream
/// OpenCV pipelines use (cv2.resize / cv2.warpAffine with INTER_LINEAR).
public struct RGBAImage: Sendable {
    public let width: Int
    public let height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4, "RGBA buffer size mismatch")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, bytes: buffer)
    }

    /// Bilinear sample at continuous pixel coordinates, clamping to the nearest edge
    /// pixel outside the image (matches cv2 BORDER_REPLICATE closely enough for faces
    /// near the frame edge).
    func sample(x: CGFloat, y: CGFloat) -> (UInt8, UInt8, UInt8) {
        let maxX = CGFloat(width - 1), maxY = CGFloat(height - 1)
        let cx = min(max(x, 0), maxX), cy = min(max(y, 0), maxY)
        let x0 = Int(cx.rounded(.down)), y0 = Int(cy.rounded(.down))
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = cx - CGFloat(x0), fy = cy - CGFloat(y0)
        func channel(_ c: Int) -> UInt8 {
            let p00 = CGFloat(bytes[(y0 * width + x0) * 4 + c])
            let p10 = CGFloat(bytes[(y0 * width + x1) * 4 + c])
            let p01 = CGFloat(bytes[(y1 * width + x0) * 4 + c])
            let p11 = CGFloat(bytes[(y1 * width + x1) * 4 + c])
            let top = p00 + (p10 - p00) * fx
            let bottom = p01 + (p11 - p01) * fx
            return UInt8(min(max((top + (bottom - top) * fy).rounded(), 0), 255))
        }
        return (channel(0), channel(1), channel(2))
    }

    /// Core ML image inputs accept 32BGRA buffers; the model's own declared color layout
    /// (RGB for ArcFace, BGR for the anti-spoof model) decides the channel order the
    /// network actually receives, so callers never reorder channels by hand.
    public func makePixelBuffer() -> CVPixelBuffer? {
        var created: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &created) == kCVReturnSuccess,
              let buffer = created else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let s = (y * width + x) * 4
                let d = y * rowBytes + x * 4
                base[d] = bytes[s + 2]
                base[d + 1] = bytes[s + 1]
                base[d + 2] = bytes[s]
                base[d + 3] = 255
            }
        }
        return buffer
    }
}

public enum FaceGeometry {
    /// InsightFace's canonical 112x112 ArcFace landmark template.
    public static let arcFaceTemplate: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    /// Least-squares similarity transform (uniform scale + rotation + translation) mapping
    /// `source` points onto `destination` points. Treating 2D points as complex numbers
    /// reduces Umeyama alignment to z = Σ conj(p)·q / Σ|p|² on mean-centered points.
    public static func similarityTransform(from source: [CGPoint], to destination: [CGPoint]) -> CGAffineTransform {
        precondition(source.count == destination.count && !source.isEmpty, "point sets must match")
        let n = CGFloat(source.count)
        let sMean = CGPoint(x: source.reduce(0) { $0 + $1.x } / n, y: source.reduce(0) { $0 + $1.y } / n)
        let dMean = CGPoint(x: destination.reduce(0) { $0 + $1.x } / n, y: destination.reduce(0) { $0 + $1.y } / n)
        var numRe: CGFloat = 0, numIm: CGFloat = 0, denom: CGFloat = 0
        for i in source.indices {
            let px = source[i].x - sMean.x, py = source[i].y - sMean.y
            let qx = destination[i].x - dMean.x, qy = destination[i].y - dMean.y
            numRe += px * qx + py * qy
            numIm += px * qy - py * qx
            denom += px * px + py * py
        }
        denom = max(denom, 1e-9)
        let a = numRe / denom, b = numIm / denom
        let tx = dMean.x - (a * sMean.x - b * sMean.y)
        let ty = dMean.y - (b * sMean.x + a * sMean.y)
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    /// Warps `frame` so `landmarks` land on the ArcFace template, producing the aligned
    /// 112x112 crop the embedding model was trained on.
    public static func alignedFace(in frame: RGBAImage, landmarks: [CGPoint], size: Int = 112) -> RGBAImage {
        let inverse = similarityTransform(from: landmarks, to: arcFaceTemplate).inverted()
        var out = [UInt8](repeating: 255, count: size * size * 4)
        for oy in 0..<size {
            for ox in 0..<size {
                let p = CGPoint(x: CGFloat(ox), y: CGFloat(oy)).applying(inverse)
                let (r, g, b) = frame.sample(x: p.x, y: p.y)
                let i = (oy * size + ox) * 4
                out[i] = r; out[i + 1] = g; out[i + 2] = b
            }
        }
        return RGBAImage(width: size, height: size, bytes: out)
    }

    /// Exact port of Silent-Face-Anti-Spoofing's CropImage._get_new_box: grow the face
    /// box by `scale` around its center (scale capped so the result fits the frame), then
    /// shift — not truncate — it back inside the frame. Returns the inclusive pixel region
    /// upstream slices with `img[top:bottom+1, left:right+1]`.
    public static func antiSpoofCropRect(faceBox box: CGRect, imageWidth: Int, imageHeight: Int, scale requested: CGFloat) -> CGRect {
        let srcW = CGFloat(imageWidth), srcH = CGFloat(imageHeight)
        let boxW = max(box.width, 1), boxH = max(box.height, 1)
        let scale = min((srcH - 1) / boxH, min((srcW - 1) / boxW, requested))
        let newW = boxW * scale, newH = boxH * scale
        let centerX = box.minX + boxW / 2, centerY = box.minY + boxH / 2
        var left = centerX - newW / 2, top = centerY - newH / 2
        var right = centerX + newW / 2, bottom = centerY + newH / 2
        if left < 0 { right -= left; left = 0 }
        if top < 0 { bottom -= top; top = 0 }
        if right > srcW - 1 { left -= right - srcW + 1; right = srcW - 1 }
        if bottom > srcH - 1 { top -= bottom - srcH + 1; bottom = srcH - 1 }
        let l = max(0, Int(left)), t = max(0, Int(top))
        let r = min(imageWidth - 1, Int(right)), b = min(imageHeight - 1, Int(bottom))
        return CGRect(x: l, y: t, width: max(1, r - l + 1), height: max(1, b - t + 1))
    }

    /// cv2.resize(INTER_LINEAR) of `rect` within `frame` to `outWidth`x`outHeight`
    /// (half-pixel-center mapping, no antialiasing — the same pixels upstream fed the model).
    public static func resize(_ frame: RGBAImage, region rect: CGRect, width outWidth: Int, height outHeight: Int) -> RGBAImage {
        let scaleX = rect.width / CGFloat(outWidth), scaleY = rect.height / CGFloat(outHeight)
        var out = [UInt8](repeating: 255, count: outWidth * outHeight * 4)
        for oy in 0..<outHeight {
            let sy = rect.minY + (CGFloat(oy) + 0.5) * scaleY - 0.5
            for ox in 0..<outWidth {
                let sx = rect.minX + (CGFloat(ox) + 0.5) * scaleX - 0.5
                let (r, g, b) = frame.sample(x: min(max(sx, rect.minX), rect.maxX - 1), y: min(max(sy, rect.minY), rect.maxY - 1))
                let i = (oy * outWidth + ox) * 4
                out[i] = r; out[i + 1] = g; out[i + 2] = b
            }
        }
        return RGBAImage(width: outWidth, height: outHeight, bytes: out)
    }
}

/// Vision-based detector: one VNDetectFaceLandmarksRequest per frame yields both the
/// box (for the anti-spoof crop) and the five alignment landmarks (for ArcFace).
public struct VisionFaceDetector: FaceDetecting {
    public init() {}

    public func detectLargestFace(in image: CGImage) throws -> DetectedFace {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { throw FaceEmbedderError.noFaceDetected }
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let marks = face.landmarks else {
            throw FaceEmbedderError.noFaceDetected
        }
        let size = CGSize(width: image.width, height: image.height)
        // Vision reports points with a bottom-left origin; flip to top-left pixel space.
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: size.height - $0.y) } ?? []
        }
        func centroid(_ pts: [CGPoint]) -> CGPoint? {
            guard !pts.isEmpty else { return nil }
            return CGPoint(x: pts.reduce(0) { $0 + $1.x } / CGFloat(pts.count), y: pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count))
        }
        let lips = points(marks.outerLips)
        guard let eyeA = centroid(points(marks.leftPupil)) ?? centroid(points(marks.leftEye)),
              let eyeB = centroid(points(marks.rightPupil)) ?? centroid(points(marks.rightEye)),
              let nose = points(marks.noseCrest).max(by: { $0.y < $1.y }) ?? centroid(points(marks.nose)),
              let mouthLeft = lips.min(by: { $0.x < $1.x }),
              let mouthRight = lips.max(by: { $0.x < $1.x }) else {
            throw FaceEmbedderError.noFaceDetected
        }
        // Template order is by image position, whatever Vision calls "left".
        let (eyeLeft, eyeRight) = eyeA.x <= eyeB.x ? (eyeA, eyeB) : (eyeB, eyeA)
        let normalized = face.boundingBox
        let box = CGRect(
            x: normalized.minX * size.width,
            y: (1 - normalized.maxY) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
        return DetectedFace(boundingBox: box, landmarks: [eyeLeft, eyeRight, nose, mouthLeft, mouthRight])
    }
}
