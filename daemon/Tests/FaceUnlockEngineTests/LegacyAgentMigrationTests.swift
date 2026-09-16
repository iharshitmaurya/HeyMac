import Testing
import Foundation
@testable import FaceUnlockEngine

private func makeFakeHome() -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

@Test func theOldLaunchAgentIsUnloadedAndRemoved() throws {
    let home = makeFakeHome()
    let plist = LegacyAgentMigration.plistURL(home: home)
    let binaries = LegacyAgentMigration.binaryDirectory(home: home)
    try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: plist)
    try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
    let enrollment = home.appendingPathComponent("Library/Application Support/faceunlock/face-centroid")
    try Data("enrolled".utf8).write(to: enrollment)
    var unloaded: [String] = []

    let migrated = LegacyAgentMigration.migrateIfNeeded(home: home) { unloaded.append($0) }

    #expect(migrated)
    #expect(unloaded == [LegacyAgentMigration.label])
    #expect(!FileManager.default.fileExists(atPath: plist.path))
    #expect(!FileManager.default.fileExists(atPath: binaries.path))
    #expect(FileManager.default.fileExists(atPath: enrollment.path), "enrollment must survive migration")
}

@Test func migrationDoesNothingWhenThereIsNoOldAgent() {
    let home = makeFakeHome()
    var unloaded: [String] = []

    #expect(LegacyAgentMigration.migrateIfNeeded(home: home) { unloaded.append($0) } == false)
    #expect(unloaded.isEmpty)
}
