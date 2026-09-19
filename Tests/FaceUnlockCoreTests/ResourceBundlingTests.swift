import Foundation
import Testing
@testable import FaceUnlockCore

@Test func arcFaceModelResourceExists() {
    let url = ModelResources.url(named: "ArcFace")
    #expect(url != nil, "ArcFace.mlpkgdata should be bundled as a resource")
}

@Test func antiSpoofModelResourceExists() {
    let url = ModelResources.url(named: "AntiSpoof")
    #expect(url != nil, "AntiSpoof.mlpkgdata should be bundled as a resource")
}

@Test func modelBundleIsFoundInAppResourcesDirectory() throws {
    let resources = makeTempDirectory()
    let model = resources.appendingPathComponent("\(ModelResources.bundleName)/Contents/Resources/Probe.mlpkgdata")
    try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
    let bundle = ModelResources.resourceBundle(searching: [resources])
    #expect(bundle.url(forResource: "Probe", withExtension: "mlpkgdata")?.resolvingSymlinksInPath().path.hasPrefix(resources.resolvingSymlinksInPath().path) == true)
}
