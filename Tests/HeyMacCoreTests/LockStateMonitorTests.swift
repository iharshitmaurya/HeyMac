import Testing
@testable import HeyMacCore

@Test func isScreenLockedReadsSessionDictionarySuccessfully() {
    // This doesn't assert a specific lock state (that depends on the machine
    // running the test) -- it asserts the underlying dlopen/dlsym/call chain
    // actually works, which is the real risk in this function (a wrong
    // framework path or symbol name would make this return nil unconditionally).
    let result = isScreenLocked()
    #expect(result != nil, "isScreenLocked() should successfully resolve and call CGSessionCopyCurrentDictionary on macOS")
}
