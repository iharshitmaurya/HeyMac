import Foundation
import Testing
@testable import FaceUnlockCore

@Test func arcFaceModelResourceExists() {
    let url = Bundle.module.url(forResource: "ArcFace", withExtension: "mlpkgdata")
    #expect(url != nil, "ArcFace.mlpkgdata should be bundled as a resource")
}

@Test func antiSpoofModelResourceExists() {
    let url = Bundle.module.url(forResource: "AntiSpoof", withExtension: "mlpkgdata")
    #expect(url != nil, "AntiSpoof.mlpkgdata should be bundled as a resource")
}
