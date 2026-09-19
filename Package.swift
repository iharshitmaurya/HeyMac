// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FaceUnlockDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FaceUnlock", targets: ["FaceUnlockApp"]),
    ],
    targets: [
        .target(
            name: "FaceUnlockCore",
            resources: [
                .copy("Resources/ArcFace.mlpkgdata"),
                .copy("Resources/AntiSpoof.mlpkgdata"),
                .copy("Resources/ArcFace.LICENSE.txt"),
                .copy("Resources/AntiSpoof.LICENSE.txt"),
            ]
        ),
        .target(
            name: "FaceUnlockEngine",
            dependencies: ["FaceUnlockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FaceUnlockApp",
            dependencies: ["FaceUnlockCore", "FaceUnlockEngine"],
            exclude: ["Animations"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FaceUnlockCoreTests",
            dependencies: ["FaceUnlockCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FaceUnlockEngineTests",
            dependencies: ["FaceUnlockEngine", "FaceUnlockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
