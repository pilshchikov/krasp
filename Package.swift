// swift-tools-version: 6.2

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
        .executableTarget(
            name: "Krasp",
            path: "Sources/Krasp",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
