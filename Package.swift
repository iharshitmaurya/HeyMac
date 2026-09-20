// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FaceUnlockDaemon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HeyMac", targets: ["FaceUnlockApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "FaceUnlockCore",
            resources: [
                .copy("Resources/ArcFace.mlpkgdata"),
                .copy("Resources/AntiSpoof.mlpkgdata"),
            ]
        ),
        .target(
            name: "FaceUnlockEngine",
            dependencies: ["FaceUnlockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FaceUnlockApp",
            dependencies: [
                "FaceUnlockCore", "FaceUnlockEngine",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Animations"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
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
