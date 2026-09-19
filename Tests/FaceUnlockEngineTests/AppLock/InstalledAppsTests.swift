import Testing
import Foundation
@testable import FaceUnlockEngine

private func makeApp(in root: URL, folder: String = "", file: String, bundleID: String,
                     name: String? = nil, backgroundOnly: Bool = false) throws {
    let contents = root.appendingPathComponent(folder).appendingPathComponent("\(file).app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL"]
    if let name { plist["CFBundleName"] = name }
    if backgroundOnly { plist["LSBackgroundOnly"] = true }
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}

private func tempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("installed-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func scanFindsAppsSortedByNameIncludingOneFolderDeep() throws {
    let root = try tempRoot()
    try makeApp(in: root, file: "Zed", bundleID: "com.example.zed", name: "Zed")
    try makeApp(in: root, file: "Alpha", bundleID: "com.example.alpha", name: "Alpha")
    try makeApp(in: root, folder: "Utilities", file: "Disk Thing", bundleID: "com.example.disk")
    let apps = InstalledApps.scan(roots: [root])
    #expect(apps.map(\.name) == ["Alpha", "Disk Thing", "Zed"])
    #expect(apps.first?.bundleID == "com.example.alpha")
}

@Test func scanSkipsBackgroundOnlyBlacklistedAndDuplicateApps() throws {
    let root = try tempRoot()
    try makeApp(in: root, file: "Helper", bundleID: "com.example.helper", backgroundOnly: true)
    try makeApp(in: root, file: "Terminal", bundleID: "com.apple.Terminal")
    try makeApp(in: root, file: "One", bundleID: "com.example.dup", name: "One")
    try makeApp(in: root, file: "OneCopy", bundleID: "com.example.dup", name: "One Copy")
    let apps = InstalledApps.scan(roots: [root])
    #expect(apps.map(\.bundleID) == ["com.example.dup"])
}

@Test func scanIgnoresMissingRoots() {
    let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)")
    #expect(InstalledApps.scan(roots: [missing]).isEmpty)
}
