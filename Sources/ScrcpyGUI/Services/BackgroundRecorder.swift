import Foundation
import SwiftUI
import Combine

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case finished(URL)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .recording: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .idle:              return "Ready"
        case .starting:          return "Starting…"
        case .recording:         return "Recording"
        case .stopping:          return "Stopping…"
        case .finished:          return "Saved"
        case .failed(let msg):   return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .recording:   return .red
        case .starting,
             .stopping:    return .orange
        case .finished:    return .green
        case .failed:      return .red
        case .idle:        return .secondary
        }
    }
}

// MARK: - Quality Preset

enum RecordingQualityPreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case p1080 = "1080p FHD"
    case p720 = "720p HD"
    case custom = "Custom"

    var id: String { rawValue }
    var label: String { rawValue }

    var summary: String {
        switch self {
        case .original: return "Native Resolution · 60 FPS · 24 Mbps"
        case .p1080:    return "1080p Limit · 60 FPS · 16 Mbps"
        case .p720:     return "720p Limit · 60 FPS · 8 Mbps"
        case .custom:   return "Custom Settings"
        }
    }
}

// MARK: - Screen Recorder

/// Manages a `scrcpy --record` process.
/// Supports both:
///  1) Headless / Background recording (`showMirrorWindow == false`)
///  2) Windowed recording with live screen displayed on Mac (`showMirrorWindow == true`)
/// Also handles live game audio through Mac speakers, quality presets, custom sliders,
/// and live elapsed time / file size metrics.
class ScreenRecorder: ObservableObject {

    // MARK: Published State

    @Published var state: RecordingState = .idle
    @Published var outputPath: String = ScreenRecorder.defaultOutputPath()
    @Published var recordingFormat: RecordingFormat = .mp4
    @Published var elapsedSeconds: Int = 0
    @Published var fileSizeBytes: Int64 = 0
    @Published var consoleOutput: String = ""

    // MARK: Display Option (Show Screen or Headless)

    /// When true: Displays the phone mirror window on Mac while recording.
    /// When false: Background recording with no window on Mac.
    @Published var showMirrorWindow: Bool = false

    // MARK: Quality & Audio Settings

    @Published var qualityPreset: RecordingQualityPreset = .original
    @Published var maxSize: Double = 0             // 0 = Native (no downscale)
    @Published var maxFPS: Double = 60             // FPS limit
    @Published var videoBitRate: Double = 24       // Mbps
    @Published var videoCodec: VideoCodec = .h264

    /// Play phone/game audio live through Mac speakers during recording.
    @Published var liveAudioPlayback: Bool = true

    /// Duplicate sound to physical phone speakers too (--audio-dup). Requires Android 10+.
    @Published var duplicateAudioToDevice: Bool = false

    /// Include audio track in the saved recording file.
    @Published var recordAudio: Bool = true

    /// Audio bitrate in kbps.
    @Published var audioBitRate: Double = 128

    // MARK: Private

    private var process: Process?
    private var elapsedTimer: AnyCancellable?
    private var fileSizeTimer: AnyCancellable?

    var scrcpyPath: String {
        PathResolver.find("scrcpy") ?? "/opt/homebrew/bin/scrcpy"
    }

    /// Determines whether modern `--no-video-playback` is supported (scrcpy 2.0+).
    private static var supportsNoVideoPlayback: Bool = {
        let path = PathResolver.find("scrcpy") ?? "/opt/homebrew/bin/scrcpy"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return true
        }
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--help"]
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8), text.contains("--no-video-playback") {
                return true
            }
        } catch {}
        return false
    }()

    // MARK: - Static Helpers

    static func defaultOutputPath() -> String {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let name = "scrcpy_recording_\(dateStamp()).mp4"
        return desktop?.appendingPathComponent(name).path ?? "/tmp/\(name)"
    }

    static func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: Date())
    }

    // MARK: - Presets

    func applyPreset(_ preset: RecordingQualityPreset) {
        qualityPreset = preset
        switch preset {
        case .original:
            maxSize = 0
            maxFPS = 60
            videoBitRate = 24
            videoCodec = .h264
        case .p1080:
            maxSize = 1080
            maxFPS = 60
            videoBitRate = 16
            videoCodec = .h264
        case .p720:
            maxSize = 720
            maxFPS = 60
            videoBitRate = 8
            videoCodec = .h264
        case .custom:
            break
        }
    }

    // MARK: - Arguments Builder

    func buildArguments(serial: String, finalPath: String, ext: String) -> [String] {
        var args: [String] = []
        args += ["--serial", serial]

        // 1. Screen Display Option (Show mirror window vs Headless)
        if !showMirrorWindow {
            // Headless / Background: Suppress video mirror window on Mac
            if Self.supportsNoVideoPlayback {
                args += ["--no-video-playback"]
                if !liveAudioPlayback {
                    args += ["--no-audio-playback"]
                }
            } else {
                args += ["--no-display"]
            }
        } else {
            // Windowed recording: Mirror window is displayed on Mac!
            if !liveAudioPlayback {
                args += ["--no-audio-playback"]
            }
        }

        // 2. Duplicate audio to phone speakers too (--audio-dup, Android 10+)
        if duplicateAudioToDevice {
            args += ["--audio-source=playback", "--audio-dup"]
        }

        // 3. Video Quality: Resolution limit
        if maxSize > 0 {
            args += ["--max-size", "\(Int(maxSize))"]
        }

        // 4. Video Quality: Max Frame Rate
        if maxFPS > 0 {
            args += ["--max-fps", "\(Int(maxFPS))"]
        }

        // 5. Video Quality: Bitrate
        if videoBitRate > 0 {
            args += ["--video-bit-rate", "\(Int(videoBitRate))M"]
        }

        // 6. Video Quality: Codec
        if videoCodec != .h264 {
            args += ["--video-codec", videoCodec.rawValue]
        }

        // 7. Audio options
        if !recordAudio {
            args += ["--no-audio"]
        } else if audioBitRate > 0 {
            args += ["--audio-bit-rate", "\(Int(audioBitRate))K"]
        }

        // 8. Output file and container format
        args += ["--record", finalPath]
        args += ["--record-format", ext]

        return args
    }

    /// Command preview for UI display.
    func commandPreview(serial: String) -> String {
        let args = buildArguments(serial: serial.isEmpty ? "<device>" : serial, finalPath: outputPath, ext: recordingFormat.rawValue)
        let escaped = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
        return "\(scrcpyPath) \(escaped.joined(separator: " "))"
    }

    // MARK: - Start

    func start(serial: String) {
        guard !state.isActive else { return }

        let resolvedPath = scrcpyPath
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
            state = .failed("scrcpy not found. Install via: brew install scrcpy")
            return
        }

        // Auto-generate a new timestamped filename each time recording starts.
        let outputURL = URL(fileURLWithPath: outputPath)
        let dir = outputURL.deletingLastPathComponent().path
        let ext = recordingFormat.rawValue
        let stem = outputURL.deletingPathExtension().lastPathComponent
            .components(separatedBy: "_")
            .filter { !$0.allSatisfy({ $0.isNumber }) }
            .joined(separator: "_")
            .trimmingCharacters(in: .init(charactersIn: "_"))

        let finalName = "\(stem.isEmpty ? "recording" : stem)_\(Self.dateStamp()).\(ext)"
        let finalPath = "\(dir)/\(finalName)"
        outputPath = finalPath

        // Ensure target directory exists.
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        state = .starting
        consoleOutput = ""
        elapsedSeconds = 0
        fileSizeBytes = 0

        let args = buildArguments(serial: serial, finalPath: finalPath, ext: ext)

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: resolvedPath)
        proc.arguments = args
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = PathResolver.combinedPATH
        proc.environment = env

        var capturedStderr = ""

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consoleOutput += text
                if text.contains("Recording started") || text.contains("Device:") {
                    if self?.state == .starting { self?.state = .recording }
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consoleOutput += text
                capturedStderr += text
                if text.contains("Recording started") || text.contains("Device:") {
                    if self?.state == .starting { self?.state = .recording }
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.process = nil
                self.stopTimers()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let fileExists = FileManager.default.fileExists(atPath: finalPath)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: finalPath)[.size] as? Int64) ?? 0

                if p.terminationStatus == 0 || self.state == .stopping {
                    if fileExists && fileSize > 0 {
                        self.fileSizeBytes = fileSize
                        self.state = .finished(URL(fileURLWithPath: finalPath))
                    } else if p.terminationStatus == 0 {
                        self.state = .finished(URL(fileURLWithPath: finalPath))
                    } else {
                        self.state = .failed("Recording stopped before data was written.")
                    }
                } else {
                    // Extract meaningful error from captured stderr if available
                    let errLine = capturedStderr
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { line in
                            let lower = line.lowercased()
                            return lower.contains("error") || lower.contains("unrecognized") || lower.contains("failed") || lower.contains("exception") || lower.contains("could not")
                        }
                        .last

                    if let errLine = errLine, !errLine.isEmpty {
                        self.state = .failed(errLine)
                    } else {
                        self.state = .failed("scrcpy exited with code \(p.terminationStatus)")
                    }
                }
            }
        }

        process = proc

        let displayCmd = ([resolvedPath] + args).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        consoleOutput = "$ \(displayCmd)\n"

        do {
            try proc.run()
            // Transition to recording after short delay if process is running
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                if self?.state == .starting, self?.process?.isRunning == true {
                    self?.state = .recording
                }
            }
            startTimers(outputPath: finalPath)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Stop

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        state = .stopping
        proc.terminate()
    }

    func reset() {
        outputPath = Self.defaultOutputPath()
        state = .idle
        consoleOutput = ""
        elapsedSeconds = 0
        fileSizeBytes = 0
    }

    // MARK: - Timers

    private func startTimers(outputPath: String) {
        elapsedTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard self?.state == .recording else { return }
                self?.elapsedSeconds += 1
            }

        fileSizeTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard self?.state == .recording else { return }
                let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
                self?.fileSizeBytes = (attrs?[.size] as? Int64) ?? 0
            }
    }

    private func stopTimers() {
        elapsedTimer?.cancel()
        fileSizeTimer?.cancel()
        elapsedTimer = nil
        fileSizeTimer = nil
    }

    // MARK: - Formatters

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var fileSizeFormatted: String {
        let mb = Double(fileSizeBytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.2f GB", mb / 1000) }
        if mb >= 1    { return String(format: "%.1f MB", mb) }
        return String(format: "%d KB", fileSizeBytes / 1000)
    }
}

// MARK: - Backward Compatibility Typealias
typealias BackgroundRecorder = ScreenRecorder
