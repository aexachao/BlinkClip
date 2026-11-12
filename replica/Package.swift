// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlinkClip",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlinkClipCore", targets: ["BlinkClipCore"]),
        .executable(name: "BlinkClip", targets: ["BlinkClip"]),
        .executable(name: "BlinkClipHelper", targets: ["BlinkClipHelper"]),
        .executable(name: "blinkclip-mcp", targets: ["BlinkClipMCP"]),
        .executable(name: "blinkclip-core-tests", targets: ["BlinkClipCoreTests"])
    ],
    targets: [
        .binaryTarget(name: "Sparkle",
                      url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
                      checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"),
        .target(name: "BlinkClipObjC", publicHeadersPath: "include"),
        .target(name: "BlinkClipCore", dependencies: ["BlinkClipObjC"], resources: [.process("BlinkClipResources")]),
        .executableTarget(name: "BlinkClip", dependencies: ["BlinkClipCore", "BlinkClipObjC", "Sparkle", "BlinkClipCapture"], path: "Sources/BlinkClip"),
        .executableTarget(name: "BlinkClipHelper"),
        .target(name: "BlinkClipCapture", path: "Vendor/capcap", exclude: ["LICENSE"]),
        .executableTarget(name: "BlinkClipMCP", dependencies: ["BlinkClipCore"]),
        .executableTarget(name: "BlinkClipCoreTests", dependencies: ["BlinkClipCore"], path: "Tests/BlinkClipCoreTests")
    ]
)
