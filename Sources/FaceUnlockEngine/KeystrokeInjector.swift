import Foundation
import ApplicationServices
import CoreGraphics
import FaceUnlockCore

public enum KeystrokeError: Error {
    case accessibilityNotGranted
    case eventCreationFailed
}

/// Types a password into the lock screen by posting synthetic key events at the HID tap
/// (the level that reaches the secure text field), then presses Return.
public final class KeystrokeInjector: PasswordTyping {
    public init() {}

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// One key press: what to send and whether to wait after releasing it.
    private struct Press {
        var virtualKey: CGKeyCode
        /// Set for text: the character is injected as Unicode so keyboard layout doesn't matter.
        var unicode: [UInt16]?
        var waitAfterRelease: Bool
    }

    private static let returnKey: CGKeyCode = 0x24
    private static let settle: TimeInterval = 0.012

    public func typeAndReturn(_ text: String) throws {
        guard Self.isAccessibilityTrusted() else { throw KeystrokeError.accessibilityNotGranted }
        let source = CGEventSource(stateID: .hidSystemState)
        for press in Self.presses(for: text) {
            try Self.send(press, source: source)
        }
    }

    /// The whole sequence: every character, then Return (which needs no trailing wait).
    private static func presses(for text: String) -> [Press] {
        let characters = text.map { Press(virtualKey: 0, unicode: Array(String($0).utf16), waitAfterRelease: true) }
        return characters + [Press(virtualKey: returnKey, unicode: nil, waitAfterRelease: false)]
    }

    private static func send(_ press: Press, source: CGEventSource?) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: press.virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: press.virtualKey, keyDown: false)
        else { throw KeystrokeError.eventCreationFailed }

        if let unicode = press.unicode {
            unicode.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                for event in [down, up] {
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
            }
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: settle)
        up.post(tap: .cghidEventTap)
        if press.waitAfterRelease { Thread.sleep(forTimeInterval: settle) }
    }
}
