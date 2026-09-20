// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HeyMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HeyMac", targets: ["HeyMacApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "HeyMacCore",
            resources: [
                .copy("Resources/ArcFace.mlpkgdata"),
                .copy("Resources/AntiSpoof.mlpkgdata"),
            ]
        ),
        .target(
            name: "HeyMacEngine",
            dependencies: ["HeyMacCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "HeyMacApp",
            dependencies: [
                "HeyMacCore", "HeyMacEngine",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Animations"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "HeyMacCoreTests",
            dependencies: ["HeyMacCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HeyMacEngineTests",
            dependencies: ["HeyMacEngine", "HeyMacCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
