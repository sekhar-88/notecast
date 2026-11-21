// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notecast",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NotecastCore",
            targets: ["NotecastCore"]
        ),
        .executable(
            name: "Notecast",
            targets: ["Notecast"]
        )
    ],
    targets: [
        .target(
            name: "NotecastCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Notecast",
            dependencies: ["NotecastCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "NotecastCoreTests",
            dependencies: ["NotecastCore"]
        )
    ]
)
