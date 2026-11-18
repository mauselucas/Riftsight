// swift-tools-version: 6.2
import PackageDescription

let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Riftsight",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Riftsight", targets: ["Riftsight"]),
    ],
    targets: [
        .target(
            name: "RiftsightCore",
            swiftSettings: approachable,
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
            ]
        ),
        .executableTarget(
            name: "Riftsight",
            dependencies: ["RiftsightCore"],
            swiftSettings: approachable + [.defaultIsolation(MainActor.self)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "RiftsightCoreTests",
            dependencies: ["RiftsightCore"],
            swiftSettings: approachable
        ),
    ]
)
