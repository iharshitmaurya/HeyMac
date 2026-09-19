import AVFoundation
import CoreImage
import Foundation

public protocol FrameSource: AnyObject {
    func start() throws
    func stop()
    /// The newest available frame, if its sequence number is greater than `sequence`.
    func frame(newerThan sequence: Int) -> (image: CGImage, sequence: Int)?
}

public enum CameraCaptureError: Error {
    case noCameraDevice
    case inputCreationFailed
}

/// On-demand camera: runs only while a verification or enrollment needs frames, so the
/// camera light is off the rest of the time. Frames from the first `warmup` seconds are
/// dropped — a webcam's auto-exposure starts dark, and those frames made bad enrollments.
public final class CameraCapture: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "faceunlock.camera")
    private let ciContext = CIContext()
    // Two locks on purpose: stopRunning() waits for in-flight delegate callbacks, so the
    // lock the callback takes (frameLock) must never be held across start/stop.
    private let sessionLock = NSLock()
    private let frameLock = NSLock()
    private let warmup: TimeInterval
    private let minFrameInterval: TimeInterval = 0.1
    private var configured = false
    private var startedAt = Date.distantFuture
    private var lastConverted = Date.distantPast
    private var latest: (image: CGImage, sequence: Int)?
    private var sequence = 0

    public init(warmup: TimeInterval = 0.8) {
        self.warmup = warmup
    }

    public func start() throws {
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
        frameLock.withLock {
            latest = nil
            startedAt = Date()
        }
        if !session.isRunning { session.startRunning() }
    }

    public func stop() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if session.isRunning { session.stopRunning() }
        frameLock.withLock {
            latest = nil
            startedAt = .distantFuture
        }
    }

    public func frame(newerThan sequence: Int) -> (image: CGImage, sequence: Int)? {
        frameLock.withLock {
            guard let latest, latest.sequence > sequence else { return nil }
            return latest
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        let wanted = frameLock.withLock { () -> Bool in
            let ok = now.timeIntervalSince(startedAt) >= warmup && now.timeIntervalSince(lastConverted) >= minFrameInterval
            if ok { lastConverted = now }
            return ok
        }
        guard wanted, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        frameLock.withLock {
            sequence += 1
            latest = (cgImage, sequence)
        }
    }
}
