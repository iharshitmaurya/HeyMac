//  Layout: [ lock ][ gap ][ clip ]. For the notch the gap is the physical cutout
//  (nothing may be drawn there); for the pill it is just negative space.

import SwiftUI

struct MinimalUnlockView: View {
    let media: ScanMedia
    let isUnlocked: Bool
    /// Inset from the silhouette's left/right edges; the caller adds the notch's flare in.
    let edgeInset: CGFloat
    let lockIconSize: CGFloat
    let mediaWidth: CGFloat
    let mediaVerticalInset: CGFloat
    /// Applied to the clip only, so the lock glyph stays steady while it breathes.
    let pulseScale: CGFloat
    let pulseOpacity: Double

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: lockIconSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .lockTransition()
                // The phase change that flips `isUnlocked` isn't itself in an animation transaction.
                .animation(.smooth(duration: NotchGeometry.minimalLockAnimationDuration), value: isUnlocked)
                .frame(width: mediaWidth)

            Spacer(minLength: 0)

            ScanAnimationView(media: media)
                .padding(.vertical, mediaVerticalInset)
                .frame(width: mediaWidth)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, edgeInset)
    }
}

private extension View {
    /// The "magic" morph is macOS 15+; older systems get the plain replace.
    @ViewBuilder func lockTransition() -> some View {
        if #available(macOS 15, *) {
            contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        } else {
            contentTransition(.symbolEffect(.replace))
        }
    }
}
