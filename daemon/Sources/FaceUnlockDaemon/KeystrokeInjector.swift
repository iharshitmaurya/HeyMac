import Foundation
import ApplicationServices
import CoreGraphics
import FaceUnlockCore

enum KeystrokeError: Error {
    case accessibilityNotGranted
    case eventCreationFailed
}

final class KeystrokeInjector: PasswordTyping {
    static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    func typeAndReturn(_ text: String) throws {
        guard Self.isAccessibilityTrusted() else {
            throw KeystrokeError.accessibilityNotGranted
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for char in text {
            try Self.postUnicode(String(char), source: source)
        }
        try Self.postReturn(source: source)
    }

    private static func postUnicode(_ unicode: String, source: CGEventSource?) throws {
        let utf16 = Array(unicode.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            }
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
    }

    private static func postReturn(source: CGEventSource?) throws {
        let returnKey: CGKeyCode = 0x24
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false) else {
            throw KeystrokeError.eventCreationFailed
        }
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
        keyUp.post(tap: .cghidEventTap)
    }
}
