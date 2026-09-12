// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FaceUnlockDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FaceUnlockCore", targets: ["FaceUnlockCore"]),
        .executable(name: "faceunlockd", targets: ["FaceUnlockDaemon"]),
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
        .executableTarget(name: "FaceUnlockDaemon", dependencies: ["FaceUnlockCore"]),
        .testTarget(name: "FaceUnlockCoreTests", dependencies: ["FaceUnlockCore"]),
    ]
)
