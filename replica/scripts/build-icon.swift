import AppKit

// Repackage the selected BlinkClip canvas; never regenerate the retired BlinkClip artwork.
let replica = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let input = replica.appendingPathComponent("Assets/BlinkClipIcon.png")
guard let taskPath = ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"] else {
    fatalError("Run through storage-guard; see README source build instructions.")
}
let task = URL(fileURLWithPath: taskPath)
let iconset = task.appendingPathComponent("build/BlinkClip.iconset")
let output = task.appendingPathComponent("out/BlinkClipAppIcon.icns")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
func run(_ command: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Icon preparation failed") }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let destination = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try run("/usr/bin/sips", ["-z", "\(size * scale)", "\(size * scale)",
                                input.path, "--out", destination.path])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path])
print(output.path)
