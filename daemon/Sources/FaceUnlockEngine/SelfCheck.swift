import Foundation
import FaceUnlockCore

/// Fast "is this build intact?" check used by `FaceUnlock --self-check` in the packaging
/// script: the models must load from the bundle and actually respond to their input.
public enum SelfCheck {
    public static func run() -> [String] {
        var problems: [String] = []

        do {
            _ = try FaceEmbedder()
        } catch {
            problems.append("face embedding model failed to load: \(error)")
        }

        do {
            let classifier = try AntiSpoofClassifier()
            let dark = try classifier.classify(patch: patch(value: 10))
            let bright = try classifier.classify(patch: patch(value: 240))
            if abs(dark.confidence - bright.confidence) < 1e-6 && dark.isLive == bright.isLive {
                problems.append("anti-spoof model returns the same answer for every input")
            }
        } catch {
            problems.append("anti-spoof model failed to load: \(error)")
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
            for name in ["uninstall-sudo-hook.sh"] {
                if !FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path) {
                    problems.append("missing bundled resource: \(name)")
                }
            }
        }

        return problems
    }

    private static func patch(value: UInt8) -> RGBAImage {
        let side = 80
        return RGBAImage(width: side, height: side, bytes: [UInt8](repeating: value, count: side * side * 4))
    }
}
