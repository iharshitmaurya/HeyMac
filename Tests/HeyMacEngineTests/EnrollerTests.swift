import Testing
import CoreGraphics
import Foundation
import HeyMacCore
@testable import HeyMacEngine

private final class FakeFrames: FrameSource {
    private(set) var started = 0
    private(set) var stopped = 0
    private var sequence = 0
    var startError: Error?

    func start() throws {
        if let startError { throw startError }
        started += 1
    }

    func stop() { stopped += 1 }

    func frame(newerThan sequence: Int) -> (image: CGImage, sequence: Int)? {
        self.sequence += 1
        return (makeTestImage(), self.sequence)
    }
}

private final class FakeSampler: EnrollmentSampling {
    enum Result { case live(Float), notLive(Float), noFace }
    var results: [Result] = []
    var defaultResult = Result.live(0.99)
    private(set) var saved: [FaceEmbedding]?
    var saveError: Error?

    func enrollmentSample(from image: CGImage) throws -> (embedding: FaceEmbedding, liveness: LivenessResult) {
        let result = results.isEmpty ? defaultResult : results.removeFirst()
        switch result {
        case .live(let confidence):
            return (FaceEmbedding(vector: [1, 0, 0]), LivenessResult(isLive: true, confidence: confidence))
        case .notLive(let confidence):
            throw VerificationPipelineError.notLive(confidence: confidence)
        case .noFace:
            throw FaceEmbedderError.noFaceDetected
        }
    }

    @discardableResult
    func saveEnrollment(_ embeddings: [FaceEmbedding]) throws -> FaceEmbedding {
        if let saveError { throw saveError }
        saved = embeddings
        return EmbeddingMath.normalized(EmbeddingMath.centroid(of: embeddings))
    }
}

/// Fake clock driven by the enroller's own sleeps, so tests never wait in real time.
private final class FakeClock {
    private var now = Date(timeIntervalSince1970: 1_000)
    func read() -> Date { now }
    func sleep(_ interval: TimeInterval) { now = now.addingTimeInterval(max(interval, 0.05)) }
}

private func makeEnroller(frames: FakeFrames, sampler: FakeSampler, clock: FakeClock, target: Int = 3, lock: NSLock = NSLock()) -> Enroller {
    Enroller(frames: frames, sampler: sampler, sessionLock: lock, target: target, timeout: 5, clock: clock.read, sleep: clock.sleep)
}

@Test func enrollmentSavesTheRequestedNumberOfSamples() {
    let frames = FakeFrames()
    let sampler = FakeSampler()
    var progress: [EnrollmentProgress] = []

    let ok = makeEnroller(frames: frames, sampler: sampler, clock: FakeClock()).run { progress.append($0) }

    #expect(ok)
    #expect(sampler.saved?.count == 3)
    #expect(progress.first == .sampleCaptured(count: 1, target: 3, liveness: 0.99))
    if case .finished(let minAgreement, _) = progress.last { #expect(minAgreement > 0.99) } else { Issue.record("expected finished, got \(String(describing: progress.last))") }
    #expect(frames.started == 1 && frames.stopped == 1)
}

@Test func framesThatFailLivenessAreReported() {
    let frames = FakeFrames()
    let sampler = FakeSampler()
    sampler.results = [.notLive(0.01), .noFace, .live(0.98), .live(0.97), .live(0.96)]
    var progress: [EnrollmentProgress] = []

    let ok = makeEnroller(frames: frames, sampler: sampler, clock: FakeClock()).run { progress.append($0) }

    #expect(ok)
    #expect(progress.contains(.rejectedNotLive(confidence: 0.01)))
    #expect(sampler.saved?.count == 3)
}

@Test func enrollmentTimesOutWithoutSaving() {
    let frames = FakeFrames()
    let sampler = FakeSampler()
    sampler.defaultResult = .noFace
    var progress: [EnrollmentProgress] = []

    let ok = makeEnroller(frames: frames, sampler: sampler, clock: FakeClock()).run { progress.append($0) }

    #expect(!ok)
    #expect(sampler.saved == nil)
    #expect(frames.stopped == 1)
    if case .failed(let message) = progress.last { #expect(message.contains("0 of 3 samples")) } else { Issue.record("expected failure, got \(String(describing: progress.last))") }
}

@Test func enrollmentRefusesWhileTheCameraIsBusy() {
    let frames = FakeFrames()
    let sampler = FakeSampler()
    let lock = NSLock()
    lock.lock()
    defer { lock.unlock() }
    var progress: [EnrollmentProgress] = []

    let ok = makeEnroller(frames: frames, sampler: sampler, clock: FakeClock(), lock: lock).run { progress.append($0) }

    #expect(!ok)
    #expect(frames.started == 0)
    if case .failed(let message) = progress.last { #expect(message.contains("busy")) } else { Issue.record("expected failure, got \(String(describing: progress.last))") }
}

@Test func cancellingStopsTheCamera() {
    let frames = FakeFrames()
    let sampler = FakeSampler()
    var progress: [EnrollmentProgress] = []

    let ok = makeEnroller(frames: frames, sampler: sampler, clock: FakeClock()).run(shouldContinue: { false }) { progress.append($0) }

    #expect(!ok)
    #expect(progress.last == .failed("Enrollment cancelled."))
    #expect(frames.stopped == 1)
}
