import SwiftUI

enum MatchState: Equatable {
    case idle, success, fail
}

/// The "did it match" indicator: a breathing ring while scanning, closing solid on a
/// result. The payoff is Apple's own lock → open morph — a native SF Symbol content
/// transition (`lock.fill` → `lock.open.fill` via `.contentTransition(.symbolEffect
/// (.replace))`), the same system-provided animation Face ID uses, not a hand-drawn
/// shape and not a borrowed asset. `TimelineView` drives the idle breathing purely
/// functionally (no `@State`, which needs a macro plugin this toolchain lacks).
struct MatchFeedbackView: View {
    let state: MatchState

    var body: some View {
        TimelineView(.animation(paused: state != .idle)) { context in
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: ringEnd(at: context.date))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.38), value: state)

                ZStack {
                    Circle().fill(tint.opacity(0.16))
                    Image(systemName: state == .success ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, options: .nonRepeating, value: state == .fail)
                }
                .frame(width: 30, height: 30)
                .scaleEffect(state == .idle ? 0.001 : 1)
                .opacity(state == .idle ? 0 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.55), value: state)
            }
        }
        .frame(width: 48, height: 48)
    }

    private var tint: Color {
        switch state {
        case .idle: return Theme.accent
        case .success: return Theme.good
        case .fail: return Theme.bad
        }
    }

    /// A result closes the ring solid; while idle, one continuous arc breathes in and
    /// out — the "still scanning" cue used everywhere else in this app.
    private func ringEnd(at date: Date) -> Double {
        guard state == .idle else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
        return 0.15 + 0.55 * (0.5 + 0.5 * sin(phase * 2 * .pi))
    }
}
