// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipGrab",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClipGrab",
            path: "ClipGrab",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .copy("Resources/DefaultPlatforms.json")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
