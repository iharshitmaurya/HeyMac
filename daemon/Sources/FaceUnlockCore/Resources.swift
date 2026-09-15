import CoreGraphics
import Foundation
import ImageIO

enum ModelResources {
    static func url(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "mlpkgdata")
    }
}

/// Loads an image file with its EXIF orientation applied, the way OpenCV's imread does.
/// Without this, a portrait phone photo decodes sideways and every model sees a rotated face.
public func loadOrientedImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
