import Testing
import Foundation
@testable import FaceUnlockEngine

private final class ScriptRecorder: @unchecked Sendable {
    var scripts: [String] = []
    var error: Error?
}

private func makeInstaller(
    resources: URL = URL(fileURLWithPath: "/Applications/FaceUnlock.app/Contents/Resources/pam"),
    existing: Set<String> = [],
    sudoLocal: String? = nil,
    recorder: ScriptRecorder = ScriptRecorder()
) -> (PamInstaller, ScriptRecorder) {
    let installer = PamInstaller(
        resourcesDirectory: resources,
        fileExists: { existing.contains($0) },
        readFile: { $0 == PamInstaller.sudoLocalPath ? sudoLocal : nil },
        runAppleScript: { script in
            recorder.scripts.append(script)
            if let error = recorder.error { throw error }
        }
    )
    return (installer, recorder)
}

@Test func statusReflectsModuleAndSudoLocal() {
    let line = "auth       sufficient     \(PamInstaller.moduleInstallPath)\n"
    #expect(makeInstaller(existing: [PamInstaller.moduleInstallPath], sudoLocal: line).0.status() == .installed)
    #expect(makeInstaller().0.status() == .notInstalled)
    #expect(makeInstaller(existing: [PamInstaller.moduleInstallPath]).0.status() == .partial)
    #expect(makeInstaller(sudoLocal: line).0.status() == .partial)
}

@Test func installRunsTheBundledScriptWithTheBundledModule() throws {
    let resources = URL(fileURLWithPath: "/Applications/FaceUnlock.app/Contents/Resources/pam")
    let script = resources.appendingPathComponent("install-pam.sh").path
    let module = resources.appendingPathComponent("pam_faceunlock.so").path
    let (installer, recorder) = makeInstaller(resources: resources, existing: [script, module])

    try installer.install()

    #expect(recorder.scripts.count == 1)
    let source = recorder.scripts[0]
    #expect(source.hasPrefix("do shell script \"/bin/bash "))
    #expect(source.hasSuffix("with administrator privileges"))
    #expect(source.contains("'\(script)'"))
    #expect(source.contains("'\(module)'"))
}

@Test func missingResourcesFailWithoutPrompting() {
    let (installer, recorder) = makeInstaller()
    #expect(throws: PamInstallerError.resourcesMissing) { try installer.install() }
    #expect(throws: PamInstallerError.resourcesMissing) { try installer.uninstall() }
    #expect(recorder.scripts.isEmpty)
}

@Test func pathsWithQuotesStayOneArgument() {
    #expect(PamInstaller.shellQuote("/Users/o'neil/FaceUnlock.app") == "'/Users/o'\\''neil/FaceUnlock.app'")
    let script = PamInstaller.administratorScript(command: "/bin/bash '/tmp/a \"b\"/x.sh'")
    #expect(script == "do shell script \"/bin/bash '/tmp/a \\\"b\\\"/x.sh'\" with administrator privileges")
}

@Test func bundledPamScriptsAreValidShell() throws {
    // .../face-id/daemon/Tests/FaceUnlockEngineTests/PamInstallerTests.swift -> .../face-id
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    for name in ["install-pam.sh", "uninstall-pam.sh"] {
        let path = repoRoot.appendingPathComponent("pam/scripts/\(name)").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(name) is not valid shell")
    }
}
