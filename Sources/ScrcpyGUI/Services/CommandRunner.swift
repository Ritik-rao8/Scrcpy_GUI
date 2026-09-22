import Foundation
import SwiftUI

/// Manages the lifecycle of a `scrcpy` child process and streams its stdout/stderr
/// to a published `consoleOutput` string for live display in the UI.
class CommandRunner: ObservableObject {

    @Published var isRunning: Bool = false
    @Published var consoleOutput: String = ""

    private var currentProcess: Process?

    /// Resolved path to the `scrcpy` binary.
    var scrcpyPath: String {
        PathResolver.find("scrcpy") ?? "/opt/homebrew/bin/scrcpy"
    }

    // MARK: - Start / Stop

    func startScrcpy(arguments: [String]) {
        guard !isRunning else { return }

        let resolvedPath = scrcpyPath
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            appendLine("[ERROR] scrcpy not found at \(resolvedPath)")
            appendLine("[INFO]  Install it via: brew install scrcpy")
            return
        }

        isRunning = true
        consoleOutput = ""

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Ensure child processes can find Homebrew binaries (ffmpeg, etc.).
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = PathResolver.combinedPATH
        process.environment = env

        // Stream stdout.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consoleOutput += text }
        }

        // Stream stderr.
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consoleOutput += text }
        }

        // Handle termination.
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.appendLine("\n[scrcpy exited with code \(proc.terminationStatus)]")
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        currentProcess = process

        let cmd = ([resolvedPath] + arguments).joined(separator: " ")
        appendLine("$ \(cmd)\n")

        do {
            try process.run()
        } catch {
            appendLine("[ERROR] \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stopScrcpy() {
        guard let proc = currentProcess, proc.isRunning else { return }
        proc.terminate()
        currentProcess = nil
    }

    func clearConsole() {
        consoleOutput = ""
    }

    // MARK: - Helpers

    private func appendLine(_ text: String) {
        consoleOutput += text + "\n"
    }
}
