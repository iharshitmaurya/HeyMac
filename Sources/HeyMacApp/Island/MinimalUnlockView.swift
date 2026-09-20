//  The compact island's content: a lock glyph on the leading side, the scan clip on the
//  trailing side, and open space between them. On a notch that space is the cutout, so
//  nothing is drawn there.

import SwiftUI

struct MinimalUnlockView: View {
    let media: ScanMedia
    let isUnlocked: Bool
    /// Distance from the outline's left and right edges. The caller adds the notch's ear width.
    let sideInset: CGFloat
    let glyphSize: CGFloat
    let clipWidth: CGFloat
    let clipInset: CGFloat
    /// Applied to the clip only, so the lock glyph stays still while the clip breathes.
    let pulseScale: CGFloat
    let pulseOpacity: Double

    var body: some View {
        HStack(spacing: 0) {
            lockGlyph
            Spacer(minLength: 0)
            clip
        }
        .padding(.horizontal, sideInset)
    }

    private var lockGlyph: some View {
        Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(.white)
            .symbolMorph()
            // The phase change that flips `isUnlocked` isn't in an animation transaction of its own.
            .animation(.smooth(duration: IslandMotion.lockMorph), value: isUnlocked)
            .frame(width: clipWidth)
    }

    private var clip: some View {
        ScanAnimationView(media: media)
            .padding(.vertical, clipInset)
            .frame(width: clipWidth)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .padding(.trailing, 4)
    }
}

private extension View {
    /// The "magic" symbol morph needs macOS 15; earlier systems get a plain replace.
    @ViewBuilder func symbolMorph() -> some View {
        if #available(macOS 15, *) {
            contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        } else {
            contentTransition(.symbolEffect(.replace))
        }
    }
}
