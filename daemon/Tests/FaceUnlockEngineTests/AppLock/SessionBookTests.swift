import Testing
import Foundation
@testable import FaceUnlockEngine

private final class Clock: @unchecked Sendable {
    var t: TimeInterval = 1_000
    func advance(minutes: Double) { t += minutes * 60 }
}

private func makeBook() -> (SessionBook, Clock) {
    let clock = Clock()
    return (SessionBook(now: { clock.t }), clock)
}

@Test func lockedUntilUnlocked() {
    let (book, _) = makeBook()
    #expect(!book.isUnlocked("a"))
    book.unlock("a", policy: .afterMinutes(5))
    #expect(book.isUnlocked("a"))
}

@Test func afterMinutesExpiresRegardlessOfFocus() {
    let (book, clock) = makeBook()
    book.unlock("a", policy: .afterMinutes(5))
    book.focusLost("a")
    clock.advance(minutes: 4.9)
    #expect(book.isUnlocked("a"))
    clock.advance(minutes: 0.2)
    #expect(!book.isUnlocked("a"))
}

@Test func everyTimeRelocksWhenFocusIsLost() {
    let (book, _) = makeBook()
    book.unlock("a", policy: .everyTime)
    #expect(book.isUnlocked("a"))
    book.focusLost("a")
    #expect(!book.isUnlocked("a"))
}

@Test func focusLossPolicyKeepsSessionIfAppReturnsInTime() {
    let (book, clock) = makeBook()
    book.unlock("a", policy: .afterFocusLossMinutes(2))
    clock.advance(minutes: 60) // focused the whole time: never expires
    #expect(book.isUnlocked("a"))
    book.focusLost("a")
    clock.advance(minutes: 1)
    book.focusGained("a")
    #expect(book.isUnlocked("a"))
    book.focusLost("a")
    clock.advance(minutes: 3)
    book.focusGained("a")
    #expect(!book.isUnlocked("a"))
}

@Test func revokeAndRevokeAllRelock() {
    let (book, _) = makeBook()
    book.unlock("a", policy: .afterMinutes(5))
    book.unlock("b", policy: .afterMinutes(5))
    book.revoke("a")
    #expect(!book.isUnlocked("a"))
    #expect(book.isUnlocked("b"))
    book.revokeAll()
    #expect(!book.isUnlocked("b"))
}
