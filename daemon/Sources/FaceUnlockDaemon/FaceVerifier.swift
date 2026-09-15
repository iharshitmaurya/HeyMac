import CoreGraphics
import Foundation
import FaceUnlockCore

/// Runs a bounded verification window over live camera frames. A match needs
/// `requiredConsecutive` consecutive frames that are both live and above the similarity
/// threshold, so one lucky frame can't unlock. Only one window runs at a time (the socket
/// and the lock-screen watcher share the camera).
final class FaceVerifier: @unchecked Sendable {
    struct Outcome {
        var matched = false
        var framesEvaluated = 0
        var framesWithoutFace = 0
        var bestSimilarity: Float = -1
        var bestLiveness: Float = 0
        var failure: String?

        var summary: String {
            if let failure { return "FAIL (\(failure))" }
            let scores = String(format: "frames=%d noFace=%d bestSimilarity=%.3f bestLiveness=%.3f", framesEvaluated, framesWithoutFace, bestSimilarity, bestLiveness)
            return (matched ? "OK " : "FAIL ") + scores
        }
    }

    private let camera: CameraCapture
    private let pipeline: VerificationPipeline
    private let busy = NSLock()

    init(camera: CameraCapture, pipeline: VerificationPipeline) {
        self.camera = camera
        self.pipeline = pipeline
    }

    func run(
        timeout: TimeInterval, requiredConsecutive: Int = 2, waitForTurn: TimeInterval = 0,
        keepGoing: () -> Bool = { true }, onFrame: ((FrameEvaluation) -> Void)? = nil
    ) -> Outcome {
        var outcome = Outcome()
        guard busy.lock(before: Date().addingTimeInterval(waitForTurn)) else {
            outcome.failure = "another verification is running"
            return outcome
        }
        defer { busy.unlock() }

        // Load the enrollment before touching the camera: no enrollment or no key access
        // fails instantly, without flashing the camera light.
        let centroid: FaceEmbedding
        do {
            centroid = try pipeline.loadEnrolledCentroid()
        } catch KeychainKeyProviderError.interactionRequired {
            outcome.failure = "keychain access needs approval: run 'faceunlockd verify' in Terminal once and choose Always Allow"
            return outcome
        } catch SecureStoreError.notFound {
            outcome.failure = "not enrolled: run 'faceunlockd enroll'"
            return outcome
        } catch {
            outcome.failure = "enrollment unavailable: \(error)"
            return outcome
        }

        let deadline = Date().addingTimeInterval(timeout)
        do {
            try camera.start()
        } catch {
            outcome.failure = "camera unavailable: \(error)"
            return outcome
        }
        defer { camera.stop() }

        var lastSequence = 0
        var consecutive = 0
        while Date() < deadline, keepGoing() {
            guard let frame = camera.frame(newerThan: lastSequence) else {
                Thread.sleep(forTimeInterval: 0.03)
                continue
            }
            lastSequence = frame.sequence
            do {
                let evaluation = try pipeline.evaluate(image: frame.image, against: centroid)
                outcome.framesEvaluated += 1
                outcome.bestSimilarity = max(outcome.bestSimilarity, evaluation.similarity)
                outcome.bestLiveness = max(outcome.bestLiveness, evaluation.liveness)
                onFrame?(evaluation)
                consecutive = evaluation.accepted ? consecutive + 1 : 0
                if consecutive >= requiredConsecutive {
                    outcome.matched = true
                    return outcome
                }
            } catch {
                outcome.framesWithoutFace += 1
                consecutive = 0
            }
        }
        return outcome
    }
}
