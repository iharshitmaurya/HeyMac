import CoreGraphics
import ImageIO
import Foundation

import FaceUnlockCore
import FaceUnlockEngine

let usage = """
usage: faceunlockd [command]
  enroll           capture your face (8 live samples)
  verify           test face verification from Terminal, printing per-frame scores
  set-password     store your login password for lock-screen unlock
  clear-password   remove the stored login password
  diagnose IMAGE [IMAGE2]   run detection/liveness/embedding on image files
"""

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/faceunlock", isDirectory: true)
try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDir.path)
enum StoredItem { static let password = "login-password" }

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "help"
if ["-h", "--help", "help"].contains(command) {
    print(usage)
    exit(0)
}

// The CLI is always run by a person, so Keychain access may prompt.
let keyProvider = CachingKeyProvider(wrapping: KeychainKeyProvider(account: NSUserName(), interactive: true))
let store = SecureStore(keyProvider: keyProvider, directory: supportDir)

switch command {
case "set-password":
    guard let first = getpass("Enter your macOS login password (used only to type it at the lock screen): ") else { exit(1) }
    let password = String(cString: first)
    guard !password.isEmpty else { print("Password cannot be empty."); exit(1) }
    guard let second = getpass("Confirm password: "), String(cString: second) == password else {
        print("Passwords did not match. Nothing was saved.")
        exit(1)
    }
    do {
        try store.save(Data(password.utf8), as: StoredItem.password)
        print("Password saved.")
        exit(0)
    } catch {
        print("Failed to save password: \(error)")
        exit(1)
    }
case "clear-password":
    let url = supportDir.appendingPathComponent(StoredItem.password)
    guard FileManager.default.fileExists(atPath: url.path) else { print("No stored password found."); exit(0) }
    do {
        try FileManager.default.removeItem(at: url)
        print("Stored password removed.")
        exit(0)
    } catch {
        print("Failed to remove stored password: \(error)")
        exit(1)
    }
case "enroll", "verify", "diagnose":
    break
default:
    print(usage)
    exit(2)
}

guard let embedder = try? FaceEmbedder(), let classifier = try? AntiSpoofClassifier() else {
    log("failed to load models")
    exit(1)
}
let pipeline = VerificationPipeline(embedder: embedder, classifier: classifier, store: store)

func formatted(_ e: FrameEvaluation) -> String {
    String(format: "liveness=%.3f%@ similarity=%.3f%@ -> %@", e.liveness, e.isLive ? "" : " (not live)",
           e.similarity, e.isMatch ? "" : " (no match)", e.accepted ? "accepted" : "rejected")
}

if command == "diagnose" {
    let paths = Array(args.dropFirst(2))
    guard !paths.isEmpty else { print(usage); exit(2) }
    let detector = VisionFaceDetector()
    var embeddings: [FaceEmbedding] = []
    for path in paths {
        guard let image = loadOrientedImage(at: URL(fileURLWithPath: path)), let frame = RGBAImage(cgImage: image) else { print("\(path): cannot read image"); exit(1) }
        do {
            let face = try detector.detectLargestFace(in: image)
            let live = try classifier.liveness(for: face, in: frame)
            let embedding = try embedder.embedding(for: face, in: frame)
            embeddings.append(embedding)
            let crop = FaceGeometry.antiSpoofCropRect(faceBox: face.boundingBox, imageWidth: frame.width, imageHeight: frame.height, scale: AntiSpoofClassifier.visionBoxScale)
            print("\(path): \(image.width)x\(image.height) face=\(face.boundingBox.integral) antiSpoofCrop=\(crop)")
            print("  landmarks=\(face.landmarks.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " "))")
            print(String(format: "  liveness=%.4f isLive=%@", live.confidence, live.isLive ? "true" : "false"))
            if let dumpDir = ProcessInfo.processInfo.environment["FACEUNLOCK_DUMP_DIR"] {
                let base = URL(fileURLWithPath: dumpDir).appendingPathComponent(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                let crops = [
                    ("aligned", FaceGeometry.alignedFace(in: frame, landmarks: face.landmarks)),
                    ("antispoof", FaceGeometry.resize(frame, region: crop, width: 80, height: 80)),
                ]
                for (suffix, patch) in crops {
                    if let cg = patch.makeCGImage(), let dest = CGImageDestinationCreateWithURL(base.appendingPathExtension("\(suffix).png") as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, cg, nil)
                        CGImageDestinationFinalize(dest)
                    }
                }
            }
            if let centroid = try? pipeline.loadEnrolledCentroid(), centroid.vector.count == embedding.vector.count {
                print(String(format: "  similarity to enrolled face=%.4f (threshold %.2f)", EmbeddingMath.cosineSimilarity(centroid, embedding), pipeline.config.matchThreshold))
            }
        } catch {
            print("\(path): \(error)")
        }
    }
    if embeddings.count == 2 {
        print(String(format: "similarity between images=%.4f", EmbeddingMath.cosineSimilarity(embeddings[0], embeddings[1])))
    }
    exit(0)
}

let camera = CameraCapture()
let verifier = FaceVerifier(camera: camera, pipeline: pipeline)

if command == "enroll" {
    // Touch the keychain first so any access dialog appears before the camera starts.
    do {
        _ = try keyProvider.fetchOrCreateKey()
    } catch {
        print("Keychain access failed: \(error)")
        exit(1)
    }
    print("Look straight at the camera in good light. Capturing live samples...")
    let enroller = Enroller(frames: camera, sampler: pipeline)
    var failure: String?
    let ok = enroller.run { progress in
        switch progress {
        case .sampleCaptured(let count, let target, let liveness):
            print(String(format: "  sample %d/%d (liveness %.3f)", count, target, liveness))
        case .rejectedNotLive(let confidence):
            print(String(format: "  frame rejected by the liveness check (%.3f) — use a real face, even lighting, no photo or screen", confidence))
        case .finished(let minAgreement, let meanAgreement):
            print(String(format: "Enrollment saved. Sample agreement with the enrolled face: min %.3f, mean %.3f.", minAgreement, meanAgreement))
            print("Test it now with: faceunlockd verify")
        case .failed(let message):
            failure = message
        }
    }
    if let failure { print(failure) }
    exit(ok ? 0 : 1)
}

if command == "verify" {
    print("Look at the camera...")
    let outcome = verifier.run(timeout: 8, onFrame: { print("  " + formatted($0)) })
    print(outcome.summary)
    exit(outcome.matched ? 0 : 1)
}

print(usage)
exit(2)
