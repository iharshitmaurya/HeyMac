import AVFoundation
import CoreImage
import Foundation

enum CameraCaptureError: Error {
    case noCameraDevice
    case inputCreationFailed
}

/// On-demand camera: runs only while a verification or enrollment needs frames, so the
/// camera light is off the rest of the time. Frames from the first `warmup` seconds are
/// dropped — a webcam's auto-exposure starts dark, and those frames made bad enrollments.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "faceunlock.camera")
    private let ciContext = CIContext()
    // Two locks on purpose: stopRunning() waits for in-flight delegate callbacks, so the
    // lock the callback takes (frameLock) must never be held across start/stop.
    private let sessionLock = NSLock()
    private let lock = NSLock()
    private let warmup: TimeInterval
    private let minFrameInterval: TimeInterval = 0.1
    private var configured = false
    private var startedAt = Date.distantFuture
    private var lastConverted = Date.distantPast
    private var latest: (image: CGImage, sequence: Int)?
    private var sequence = 0

    init(warmup: TimeInterval = 0.8) {
        self.warmup = warmup
    }

    func start() throws {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video) else { throw CameraCaptureError.noCameraDevice }
            guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                throw CameraCaptureError.inputCreationFailed
            }
            session.beginConfiguration()
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            configured = true
        }
        lock.withLock {
            latest = nil
            startedAt = Date()
        }
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if session.isRunning { session.stopRunning() }
        lock.withLock {
            latest = nil
            startedAt = .distantFuture
        }
    }

    /// The newest post-warmup frame, if it's newer than `sequence`.
    func frame(newerThan sequence: Int) -> (image: CGImage, sequence: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard let latest, latest.sequence > sequence else { return nil }
        return latest
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        lock.lock()
        let wanted = now.timeIntervalSince(startedAt) >= warmup && now.timeIntervalSince(lastConverted) >= minFrameInterval
        if wanted { lastConverted = now }
        lock.unlock()
        guard wanted, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        lock.lock()
        sequence += 1
        latest = (cgImage, sequence)
        lock.unlock()
    }
}
