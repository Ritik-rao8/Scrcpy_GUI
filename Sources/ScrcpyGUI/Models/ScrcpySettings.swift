import Foundation
import SwiftUI

// MARK: - Recording Format

enum RecordingFormat: String, CaseIterable, Identifiable {
    case mp4
    case mkv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mp4: return "MP4"
        case .mkv: return "MKV"
        }
    }
}

// MARK: - Video Codec

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264
    case h265
    case av1
    case vp8
    case vp9

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h264: return "H.264 (default, best compatibility)"
        case .h265: return "H.265 / HEVC (better quality, needs Android 10+)"
        case .av1:  return "AV1 (best quality, needs Android 14+)"
        case .vp8:  return "VP8"
        case .vp9:  return "VP9"
        }
    }

    var shortLabel: String { rawValue.uppercased() }
}

// MARK: - Scrcpy Settings

/// Observable model that holds every configurable scrcpy option.
/// The `buildArguments` method converts the current state into CLI flags.
class ScrcpySettings: ObservableObject {

    // MARK: Display

    /// 0 means "no limit" (native resolution).
    @Published var maxSize: Double = 0
    @Published var maxFPS: Double = 60
    /// Video bitrate in Mbps.
    @Published var videoBitRate: Double = 8
    /// Audio bitrate in Kbps.
    @Published var audioBitRate: Double = 128

    // MARK: Recording

    @Published var enableRecording: Bool = false
    @Published var recordingFormat: RecordingFormat = .mp4
    @Published var recordingPath: String = ""

    // MARK: Device Options

    @Published var turnScreenOff: Bool = false
    @Published var stayAwake: Bool = false
    @Published var noAudio: Bool = false
    @Published var showTouches: Bool = false
    @Published var noControl: Bool = false

    // MARK: Codec & Buffering

    /// Which video codec to use for encoding on the device.
    @Published var videoCodec: VideoCodec = .h264
    /// Extra audio buffering in milliseconds (0 = disabled). Useful on Wi-Fi to reduce stutter.
    @Published var audioBufferMs: Double = 0

    // MARK: Window Options

    @Published var alwaysOnTop: Bool = false
    @Published var fullscreen: Bool = false
    @Published var borderless: Bool = false
    @Published var windowTitle: String = ""

    // MARK: - Command Builder

    /// Builds the complete argument list for the `scrcpy` process.
    func buildArguments(serial: String) -> [String] {
        var args: [String] = []

        // Device selection
        args += ["--serial", serial]

        // Display
        if maxSize > 0 {
            args += ["--max-size", "\(Int(maxSize))"]
        }
        args += ["--max-fps", "\(Int(maxFPS))"]
        args += ["--video-bit-rate", "\(Int(videoBitRate))M"]

        // Video codec (only add flag when not default to keep command cleaner)
        if videoCodec != .h264 {
            args += ["--video-codec", videoCodec.rawValue]
        }

        // Audio
        if noAudio {
            args.append("--no-audio")
        } else {
            args += ["--audio-bit-rate", "\(Int(audioBitRate))K"]
            if audioBufferMs > 0 {
                args += ["--audio-buffer", "\(Int(audioBufferMs))"]
            }
        }

        // Device options
        if turnScreenOff { args.append("--turn-screen-off") }
        if stayAwake     { args.append("--stay-awake") }
        if showTouches   { args.append("--show-touches") }
        if noControl     { args.append("--no-control") }

        // Window options
        if alwaysOnTop { args.append("--always-on-top") }
        if fullscreen  { args.append("--fullscreen") }
        if borderless  { args.append("--window-borderless") }
        if !windowTitle.isEmpty {
            args += ["--window-title", windowTitle]
        }

        // Recording
        if enableRecording && !recordingPath.isEmpty {
            args += ["--record", recordingPath]
            args += ["--record-format", recordingFormat.rawValue]
        }

        return args
    }

    /// Returns a human-readable preview of the command that will be executed.
    func commandPreview(serial: String, scrcpyPath: String) -> String {
        let args = buildArguments(serial: serial)
        let escaped = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }
        return "\(scrcpyPath) \(escaped.joined(separator: " "))"
    }
}
