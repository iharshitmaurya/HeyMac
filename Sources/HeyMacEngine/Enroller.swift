import CoreGraphics
import Foundation
import HeyMacCore

public protocol EnrollmentSampling: AnyObject {
    func enrollmentSample(from image: CGImage) throws -> (embedding: FaceEmbedding, liveness: LivenessResult)
    @discardableResult
    func saveEnrollment(_ embeddings: [FaceEmbedding]) throws -> FaceEmbedding
}

extension VerificationPipeline: EnrollmentSampling {}

public enum EnrollmentProgress: Equatable, Sendable {
    case sampleCaptured(count: Int, target: Int, liveness: Float)
    case rejectedNotLive(confidence: Float)
    case noFaceDetected
    case frameRejected(String)
    case finished(minAgreement: Float, meanAgreement: Float)
    case failed(String)
}

/// Collects `target` spaced-out live samples from the camera and saves their centroid as
/// the enrolled face. Frames without a face are skipped silently; frames that fail the
/// liveness check are reported so the UI can explain what to change.
public final class Enroller {
    private let frames: FrameSource
    private let sampler: EnrollmentSampling
    private let sessionLock: NSLock
    public let target: Int
    private let sampleSpacing: TimeInterval
    private let timeout: TimeInterval
    private let clock: () -> Date
    private let sleep: (TimeInterval) -> Void

    public init(
        frames: FrameSource, sampler: EnrollmentSampling, sessionLock: NSLock = NSLock(), target: Int = 8,
        sampleSpacing: TimeInterval = 0.25, timeout: TimeInterval = 40,
        clock: @escaping () -> Date = Date.init, sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.frames = frames
        self.sampler = sampler
        self.sessionLock = sessionLock
        self.target = target
        self.sampleSpacing = sampleSpacing
        self.timeout = timeout
        self.clock = clock
        self.sleep = sleep
    }

    @discardableResult
    public func run(shouldContinue: () -> Bool = { true }, onProgress: (EnrollmentProgress) -> Void) -> Bool {
        guard sessionLock.try() else {
            onProgress(.failed("The camera is busy with another check. Try again in a moment."))
            return false
        }
        defer { sessionLock.unlock() }

        do {
            try frames.start()
        } catch {
            onProgress(.failed("Camera unavailable: \(error)"))
            return false
        }
        defer { frames.stop() }

        var samples: [FaceEmbedding] = []
        var lastSequence = 0
        var lastSampleAt = Date.distantPast
        var lastLivenessReport = Date.distantPast
        var lastAnalysisReport = Date.distantPast
        var noFaceFrames = 0
        var livenessRejectedFrames = 0
        var bestLiveness: Float = 0
        var analysisFailures = 0
        var lastAnalysisFailure: String?
        let deadline = clock().addingTimeInterval(timeout)

        while samples.count < target {
            guard shouldContinue() else {
                onProgress(.failed("Enrollment cancelled."))
                return false
            }
            let now = clock()
            guard now < deadline else {
                let reason: String
                if livenessRejectedFrames > 0 {
                    reason = String(format: "Found a face, but liveness was not confirmed (best confidence %.2f). Face the camera in bright, even light and try again.", bestLiveness)
                } else if noFaceFrames > 0 {
                    reason = "Could not find a usable face in the camera frames. Center your face, keep both eyes visible, and improve the lighting."
                } else if analysisFailures > 0 {
                    reason = "Face analysis failed: \(lastAnalysisFailure ?? "unknown error")"
                } else {
                    reason = "No camera frames arrived. Check camera access and try again."
                }
                onProgress(.failed("Captured \(samples.count) of \(target) samples in \(Int(timeout))s. \(reason)"))
                return false
            }
            guard now.timeIntervalSince(lastSampleAt) >= sampleSpacing, let frame = frames.frame(newerThan: lastSequence) else {
                sleep(0.03)
                continue
            }
            lastSequence = frame.sequence
            do {
                let sample = try sampler.enrollmentSample(from: frame.image)
                samples.append(sample.embedding)
                lastSampleAt = now
                onProgress(.sampleCaptured(count: samples.count, target: target, liveness: sample.liveness.confidence))
            } catch VerificationPipelineError.notLive(let confidence) {
                livenessRejectedFrames += 1
                bestLiveness = max(bestLiveness, confidence)
                if now.timeIntervalSince(lastLivenessReport) >= 2 {
                    lastLivenessReport = now
                    onProgress(.rejectedNotLive(confidence: confidence))
                }
                sleep(0.03)
            } catch FaceEmbedderError.noFaceDetected {
                noFaceFrames += 1
                if now.timeIntervalSince(lastAnalysisReport) >= 2 {
                    lastAnalysisReport = now
                    onProgress(.noFaceDetected)
                }
                sleep(0.03)
            } catch {
                analysisFailures += 1
                lastAnalysisFailure = String(describing: error)
                if now.timeIntervalSince(lastAnalysisReport) >= 2 {
                    lastAnalysisReport = now
                    onProgress(.frameRejected(lastAnalysisFailure ?? "unknown error"))
                }
                sleep(0.03)
            }
        }

        do {
            let centroid = try sampler.saveEnrollment(samples)
            let agreement = samples.map { EmbeddingMath.cosineSimilarity(centroid, $0) }
            onProgress(.finished(
                minAgreement: agreement.min() ?? 0,
                meanAgreement: agreement.reduce(0, +) / Float(agreement.count)
            ))
            return true
        } catch {
            onProgress(.failed("Saving enrollment failed: \(error)"))
            return false
        }
    }
}
