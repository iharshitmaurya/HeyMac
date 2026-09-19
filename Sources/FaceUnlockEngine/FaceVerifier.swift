import CoreGraphics
import Foundation
import FaceUnlockCore

public struct VerificationOutcome: Equatable, Sendable {
    public var matched = false
    public var framesEvaluated = 0
    public var framesWithoutFace = 0
    public var bestSimilarity: Float = -1
    public var bestLiveness: Float = 0
    public var failure: String?

    public init() {}

    public var summary: String {
        if let failure { return "FAIL (\(failure))" }
        let scores = String(format: "frames=%d noFace=%d bestSimilarity=%.3f bestLiveness=%.3f",
                            framesEvaluated, framesWithoutFace, bestSimilarity, bestLiveness)
        return (matched ? "OK " : "FAIL ") + scores
    }
}

public protocol FaceMatching: AnyObject {
    func run(timeout: TimeInterval, requiredConsecutive: Int, waitForTurn: TimeInterval,
             keepGoing: () -> Bool) -> VerificationOutcome
}

/// Runs a bounded verification window over live camera frames. A match needs
/// `requiredConsecutive` consecutive frames that are both live and above the similarity
/// threshold, so one lucky frame can't unlock. `sessionLock` is shared by everything that
/// uses the camera, so only one window or enrollment runs at a time.
public final class FaceVerifier: FaceMatching, @unchecked Sendable {
    private let camera: FrameSource
    private let pipeline: VerificationPipeline
    private let sessionLock: NSLock

    public init(camera: FrameSource, pipeline: VerificationPipeline, sessionLock: NSLock = NSLock()) {
        self.camera = camera
        self.pipeline = pipeline
        self.sessionLock = sessionLock
    }

    public func run(
        timeout: TimeInterval, requiredConsecutive: Int = 2, waitForTurn: TimeInterval = 0,
        keepGoing: () -> Bool = { true }
    ) -> VerificationOutcome {
        var outcome = VerificationOutcome()
        guard sessionLock.lock(before: Date().addingTimeInterval(waitForTurn)) else {
            outcome.failure = "camera busy with another verification"
            return outcome
        }
        defer { sessionLock.unlock() }

        // Load the enrollment before touching the camera: no enrollment or no key access
        // fails instantly, without flashing the camera light.
        let centroid: FaceEmbedding
        do {
            centroid = try pipeline.loadEnrolledCentroid()
        } catch KeychainKeyProviderError.interactionRequired {
            outcome.failure = "keychain access needs approval: open FaceUnlock and run Test Now"
            return outcome
        } catch SecureStoreError.notFound {
            outcome.failure = "not enrolled"
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
