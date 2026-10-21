// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RemoteHandy",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "RemoteHandyCore",
            targets: ["RemoteHandyCore"]
        ),
        .executable(
            name: "remote-handy-fixture-tests",
            targets: ["RemoteHandyFixtureTests"]
        ),
        .executable(
            name: "remote-handy-donor-app",
            targets: ["RemoteHandyDonorApp"]
        ),
        .executable(
            name: "remote-handy-menubar",
            targets: ["RemoteHandyMenuBar"]
        ),
    ],
    targets: [
        .target(
            name: "RemoteHandyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RemoteHandyFixtureTests",
            dependencies: ["RemoteHandyCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "RemoteHandyDonorApp",
            dependencies: ["RemoteHandyCore"]
        ),
        .executableTarget(
            name: "RemoteHandyMenuBar",
            dependencies: ["RemoteHandyCore"]
        ),
    ]
)
