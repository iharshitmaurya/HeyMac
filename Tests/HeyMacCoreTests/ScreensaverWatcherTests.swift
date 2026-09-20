import Testing
@testable import HeyMacCore

final class FakeLockChecker: LockStateChecking {
    var responses: [Bool?]
    private var index = 0
    init(responses: [Bool?]) { self.responses = responses }
    func isLocked() -> Bool? {
        guard index < responses.count else { return responses.last ?? nil }
        defer { index += 1 }
        return responses[index]
    }
}

final class FakeTypist: PasswordTyping {
    var typedText: String?
    var shouldThrow: Error?
    func typeAndReturn(_ text: String) throws {
        if let error = shouldThrow { throw error }
        typedText = text
    }
}

@Test func typesWhenLockedBeforeAndAfterWake() throws {
    let lockChecker = FakeLockChecker(responses: [true, true])
    let typist = FakeTypist()
    var wakeCalled = false
    let watcher = ScreensaverWatcher(lockChecker: lockChecker, typist: typist, wakeDisplay: { wakeCalled = true })

    try watcher.attemptUnlock(password: "hunter2")

    #expect(wakeCalled == true)
    #expect(typist.typedText == "hunter2")
}

@Test func doesNotTypeIfUnlockedBeforeWake() throws {
    let lockChecker = FakeLockChecker(responses: [false])
    let typist = FakeTypist()
    let watcher = ScreensaverWatcher(lockChecker: lockChecker, typist: typist)

    #expect(throws: ScreensaverWatcherError.lockStateChangedBeforeTyping) {
        try watcher.attemptUnlock(password: "hunter2")
    }
    #expect(typist.typedText == nil)
}

@Test func doesNotTypeIfUnlockedBetweenWakeAndTyping() throws {
    // Locked on first check, but unlocked by the time the second (post-wake) check runs --
    // this is exactly the race the double-check exists to catch.
    let lockChecker = FakeLockChecker(responses: [true, false])
    let typist = FakeTypist()
    let watcher = ScreensaverWatcher(lockChecker: lockChecker, typist: typist)

    #expect(throws: ScreensaverWatcherError.lockStateChangedBeforeTyping) {
        try watcher.attemptUnlock(password: "hunter2")
    }
    #expect(typist.typedText == nil)
}

@Test func doesNotTypeIfLockStateUnknown() throws {
    let lockChecker = FakeLockChecker(responses: [nil])
    let typist = FakeTypist()
    let watcher = ScreensaverWatcher(lockChecker: lockChecker, typist: typist)

    #expect(throws: ScreensaverWatcherError.lockStateUnknown) {
        try watcher.attemptUnlock(password: "hunter2")
    }
    #expect(typist.typedText == nil)
}

@Test func propagatesTypistError() throws {
    let lockChecker = FakeLockChecker(responses: [true, true])
    let typist = FakeTypist()
    typist.shouldThrow = ScreensaverWatcherError.lockStateChangedBeforeTyping // any Error works for this test
    let watcher = ScreensaverWatcher(lockChecker: lockChecker, typist: typist)

    #expect(throws: ScreensaverWatcherError.lockStateChangedBeforeTyping) {
        try watcher.attemptUnlock(password: "hunter2")
    }
}
