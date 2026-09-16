import CoreGraphics
import Foundation
import FaceUnlockCore
@testable import FaceUnlockEngine

func makeTestSettings(configure: (EngineSettings) -> Void = { _ in }) -> EngineSettings {
    let defaults = UserDefaults(suiteName: "faceunlock-tests-\(UUID().uuidString)")!
    let settings = EngineSettings(defaults: defaults)
    settings.setupComplete = true
    configure(settings)
    return settings
}

func makeTestImage(width: Int = 8, height: Int = 8) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    )!
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func matchedOutcome() -> VerificationOutcome {
    var outcome = VerificationOutcome()
    outcome.matched = true
    outcome.framesEvaluated = 2
    outcome.bestSimilarity = 0.9
    outcome.bestLiveness = 0.99
    return outcome
}

final class FakeMatcher: FaceMatching {
    var outcome = VerificationOutcome()
    private(set) var callCount = 0

    func run(timeout: TimeInterval, requiredConsecutive: Int, waitForTurn: TimeInterval,
             keepGoing: () -> Bool, onFrame: ((FrameEvaluation) -> Void)?) -> VerificationOutcome {
        callCount += 1
        return outcome
    }
}

/// Mutable stand-in for the machine's lock/display/permission state.
final class FakeSystem {
    var locked: Bool? = true
    var displayAwake = true
    var accessibilityTrusted = true
    var password = "hunter2"
    var passwordError: Error?
    private(set) var slept: [TimeInterval] = []

    func environment() -> LockScreenEnvironment {
        LockScreenEnvironment(
            isLocked: { self.locked },
            displayIsAwake: { self.displayAwake },
            accessibilityTrusted: { self.accessibilityTrusted },
            loadPassword: {
                if let error = self.passwordError { throw error }
                return self.password
            },
            wakeDisplay: {},
            sleep: { self.slept.append($0) }
        )
    }
}

final class FakeTypist: PasswordTyping {
    private let system: FakeSystem
    /// Whether typing this password actually unlocks the Mac.
    private let unlocks: Bool
    private(set) var typed: [String] = []

    init(system: FakeSystem, unlocks: Bool) {
        self.system = system
        self.unlocks = unlocks
    }

    func typeAndReturn(_ text: String) throws {
        typed.append(text)
        if unlocks { system.locked = false }
    }
}

final class EventRecorder {
    private(set) var events: [EngineEvent] = []
    func record(_ event: EngineEvent) { events.append(event) }
}
