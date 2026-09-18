import SwiftUI

enum MatchState: Equatable {
    case idle, success, fail
}

/// The wizard's "did it match" indicator: the same still-then-clip animation the notch
/// island plays on the lock screen. The clips are opaque black, so they sit in a rounded tile.
struct MatchFeedbackView: View {
    let state: MatchState

    var body: some View {
        ScanAnimationView(media: media)
            .frame(width: 44, height: 44)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var media: ScanMedia {
        switch state {
        case .idle: return .idle
        case .success: return .success
        case .fail: return .failure
        }
    }
}
