import Testing
import Foundation
@testable import HeyMacEngine

private final class ScriptRecorder: @unchecked Sendable {
    var scripts: [String] = []
}

private let script = URL(fileURLWithPath: "/Applications/HeyMac.app/Contents/Resources/uninstall-sudo-hook.sh")

private func makeCleanup(existing: Set<String> = [], sudoLocal: String? = nil, recorder: ScriptRecorder = ScriptRecorder()) -> LegacySudoCleanup {
    LegacySudoCleanup(
        scriptURL: script,
        fileExists: { existing.contains($0) },
        readFile: { $0 == LegacySudoCleanup.sudoLocalPath ? sudoLocal : nil },
        runAppleScript: { recorder.scripts.append($0) }
    )
}

@Test func leftoverIsDetectedFromTheModuleOrTheSudoLocalLine() {
    #expect(makeCleanup().leftoverDetected() == false)
    #expect(makeCleanup(existing: [LegacySudoCleanup.moduleInstallPath]).leftoverDetected())
    #expect(makeCleanup(sudoLocal: "auth sufficient \(LegacySudoCleanup.moduleInstallPath)\n").leftoverDetected())
    #expect(makeCleanup(sudoLocal: "auth sufficient pam_tid.so\n").leftoverDetected() == false)
}

@Test func removeRunsTheBundledScriptWithAdministratorPrivileges() throws {
    let recorder = ScriptRecorder()
    try makeCleanup(existing: [script.path], recorder: recorder).remove()
    #expect(recorder.scripts.count == 1)
    #expect(recorder.scripts[0].contains("uninstall-sudo-hook.sh"))
    #expect(recorder.scripts[0].hasSuffix("with administrator privileges"))
}

@Test func removeFailsWhenTheScriptIsNotBundled() {
    #expect(throws: LegacySudoCleanupError.scriptMissing) { try makeCleanup().remove() }
}
