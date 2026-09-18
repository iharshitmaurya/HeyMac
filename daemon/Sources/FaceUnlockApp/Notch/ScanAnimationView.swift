//  Shows the still while scanning, then plays a result clip once and holds its final
//  frame — deliberately not looping, since each clip ends on a meaningful resolved state.

import AVFoundation
import AppKit
import SwiftUI

/// Which media the overlay is showing. `.idle` is a still image (the first frame of
/// the success clip) so the swap into a playing clip is seamless.
enum ScanMedia: Equatable {
    case idle, success, failure

    var clipName: String? {
        switch self {
        case .idle: return nil
        case .success: return "unlockanimation"
        case .failure: return "unsuccessfulunlockanimation"
        }
    }
}

enum AnimationAssets {
    /// In the built app the assets sit in Contents/Resources/Animations; under `swift run`
    /// there is no app bundle, so fall back to the source tree.
    static func url(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Animations") {
            return url
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Animations/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
}

struct ScanAnimationView: NSViewRepresentable {
    let media: ScanMedia

    func makeNSView(context: Context) -> ScanAnimationHostView {
        let view = ScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: ScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
    }
}

final class ScanAnimationHostView: NSView {
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let stillLayer = CALayer()
    private var currentMedia: ScanMedia?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackReveal: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()

        stillLayer.contentsGravity = .resizeAspect
        if let url = AnimationAssets.url("unlockstatic", "png"), let image = NSImage(contentsOf: url) {
            stillLayer.contents = image
        }
        layer?.addSublayer(stillLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        stillLayer.frame = bounds
        CATransaction.commit()
    }

    func apply(media: ScanMedia) {
        guard media != currentMedia else { return }
        currentMedia = media
        readyObservation = nil
        fallbackReveal?.cancel()
        teardownPlayer()

        guard let clip = media.clipName, let url = AnimationAssets.url(clip, "mp4") else {
            show(clip: false)
            return
        }

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true // this can play at the lock screen
        newPlayer.actionAtItemEnd = .none // pause on the final frame instead of rewinding
        playerLayer.player = newPlayer
        player = newPlayer

        // Wait for the first decoded frame rather than a fixed delay, which raced decode
        // time and flashed black.
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async {
                self?.fallbackReveal?.cancel()
                self?.show(clip: true)
                self?.readyObservation = nil
            }
        }
        let fallback = DispatchWorkItem { [weak self] in self?.show(clip: true) }
        fallbackReveal = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)

        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    /// Implicit actions off, or toggling `isHidden` cross-fades both layers.
    private func show(clip: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.isHidden = !clip
        stillLayer.isHidden = clip
        CATransaction.commit()
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
        playerLayer.player = nil
    }
}
