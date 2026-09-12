import AVFoundation
import CoreImage
import Foundation

enum CameraCaptureError: Error {
    case noCameraDevice
    case inputCreationFailed
}

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let onFrame: (CGImage) -> Void
    private let ciContext = CIContext()
    private let queue = DispatchQueue(label: "faceunlock.cameracapture")

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraCaptureError.noCameraDevice
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw CameraCaptureError.inputCreationFailed
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)

        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame(cgImage)
    }
}
