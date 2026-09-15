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
