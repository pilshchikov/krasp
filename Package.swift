// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Krasp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Krasp", targets: ["Krasp"])
    ],
    targets: [
        .target(name: "CDPDFNet", path: "Sources/CDPDFNet", exclude: ["vendor/LICENSE"]),
        .executableTarget(
            name: "Krasp",
            dependencies: ["CDPDFNet"],
            path: "Sources/Krasp",
            exclude: ["Resources"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(name: "KraspTests", dependencies: ["Krasp"])
    ]
)
