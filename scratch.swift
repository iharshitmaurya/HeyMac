import AVFoundation

let session = AVCaptureSession()
guard let device = AVCaptureDevice.default(for: .video) else { print("No camera"); exit(0) }
guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { print("input error"); exit(0) }
session.addInput(input)
let output = AVCaptureVideoDataOutput()
class Delegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var count = 0
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        count += 1
        let metadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [String: Any]
        let exif = metadata?["{Exif}"] as? [String: Any]
        let brightness = exif?["BrightnessValue"] as? Double
        print("Count \(count) Brightness: \(String(describing: brightness))")
        if count > 5 { exit(0) }
    }
}
let delegate = Delegate()
output.setSampleBufferDelegate(delegate, queue: DispatchQueue.main)
session.addOutput(output)
session.startRunning()
RunLoop.main.run()
