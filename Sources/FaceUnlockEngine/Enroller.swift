import CoreGraphics
import Foundation
import FaceUnlockCore

public protocol EnrollmentSampling: AnyObject {
    func enrollmentSample(from image: CGImage) throws -> (embedding: FaceEmbedding, liveness: LivenessResult)
    @discardableResult
    func saveEnrollment(_ embeddings: [FaceEmbedding]) throws -> FaceEmbedding
}

extension VerificationPipeline: EnrollmentSampling {}

public enum EnrollmentProgress: Equatable, Sendable {
    case sampleCaptured(count: Int, target: Int, liveness: Float)
    case rejectedNotLive(confidence: Float)
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
        let deadline = clock().addingTimeInterval(timeout)

        while samples.count < target {
            guard shouldContinue() else {
                onProgress(.failed("Enrollment cancelled."))
                return false
            }
            let now = clock()
            guard now < deadline else {
                onProgress(.failed("Captured \(samples.count) of \(target) samples in \(Int(timeout))s. Check the lighting, keep your face centered, and try again."))
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
                if now.timeIntervalSince(lastLivenessReport) >= 2 {
                    lastLivenessReport = now
                    onProgress(.rejectedNotLive(confidence: confidence))
                }
                sleep(0.03)
            } catch {
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
