import Foundation

/// Utility to locate `adb` and `scrcpy` binaries on the system.
/// Searches common Homebrew install paths for both Apple Silicon and Intel Macs.
struct PathResolver {

    /// Common directories where Homebrew and system binaries live.
    private static let searchDirectories = [
        "/opt/homebrew/bin",   // Apple Silicon Homebrew
        "/usr/local/bin",      // Intel Homebrew
        "/usr/bin",
        "/bin",
    ]

    /// Returns the full path to a binary if found, otherwise `nil`.
    static func find(_ binaryName: String) -> String? {
        for dir in searchDirectories {
            let path = "\(dir)/\(binaryName)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// A combined PATH string suitable for setting on a `Process.environment`
    /// so that child processes (like scrcpy finding ffmpeg) also resolve correctly.
    static var combinedPATH: String {
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extra = searchDirectories.joined(separator: ":")
        return "\(extra):\(existing)"
    }
}
