// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FaceUnlockDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FaceUnlockCore", targets: ["FaceUnlockCore"]),
        .library(name: "FaceUnlockEngine", targets: ["FaceUnlockEngine"]),
        .executable(name: "faceunlockd", targets: ["FaceUnlockDaemon"]),
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
            name: "FaceUnlockDaemon",
            dependencies: ["FaceUnlockCore", "FaceUnlockEngine"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FaceUnlockDaemon/Info.plist",
                ])
            ]
        ),
        .executableTarget(
            name: "FaceUnlockApp",
            dependencies: ["FaceUnlockCore", "FaceUnlockEngine"],
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
