import CoreGraphics
import Foundation
import ImageIO

enum ModelResources {
    static let bundleName = "FaceUnlockDaemon_FaceUnlockCore.bundle"

    static func url(named name: String) -> URL? {
        resourceBundle().url(forResource: name, withExtension: "mlpkgdata")
    }

    /// SwiftPM's generated `Bundle.module` only looks beside the executable and at the
    /// absolute build directory, so inside FaceUnlock.app (bundle copied to
    /// Contents/Resources) it would find the models only on the Mac that built the app —
    /// and fatalError everywhere else. Look in the app's resources first.
    static func resourceBundle(searching directories: [URL] = defaultSearchDirectories) -> Bundle {
        for directory in directories {
            let url = directory.appendingPathComponent(bundleName)
            if FileManager.default.fileExists(atPath: url.path), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.module
    }

    static var defaultSearchDirectories: [URL] {
        [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
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
