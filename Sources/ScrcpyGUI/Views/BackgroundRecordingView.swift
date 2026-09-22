import SwiftUI
import AppKit

// MARK: - Screen Recording View

/// A full-featured recording studio view.
/// Supports both:
///  1) Windowed recording (displaying phone mirror window on Mac while recording)
///  2) Background recording (no window displayed on Mac)
/// Includes live elapsed timer, file size, quality presets, custom sliders,
/// sound routing (live Mac game audio), and output destination chooser.
struct ScreenRecordingView: View {

    @ObservedObject var recorder: ScreenRecorder
    var settings: ScrcpySettings? = nil
    var deviceInfo: DeviceInfo? = nil
    var deviceSerial: String

    @State private var pulseAnimation: Bool = false
    @State private var isFineTuningExpanded: Bool = false
    @State private var isHoveringQualityBar: Bool = false

    /// Dynamic upper bound for resolution slider.
    private var maxResolutionLimit: Double {
        Double(deviceInfo?.maxDimension ?? 2560)
    }

    /// Dynamic upper bound for frame rate slider.
    private var maxFPSLimit: Double {
        deviceInfo?.refreshRate ?? 120
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 14) {
            // Live Status Banner & Metrics
            statusHeaderCard

            // Primary Action Card (Start/Stop, Display Option & Presets)
            primaryActionCard

            // Sound & Live Audio Routing Card
            soundRoutingCard

            // Video Quality Fine-Tuning Card
            videoQualityCard

            // Save Destination Card
            destinationCard
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            if recorder.qualityPreset == .custom {
                isFineTuningExpanded = true
            }
        }
    }

    // MARK: - Status Header Card

    private var statusHeaderCard: some View {
        HStack(spacing: 12) {
            // Pulsing dot indicator
            ZStack {
                if recorder.state == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .scaleEffect(pulseAnimation ? 1.6 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.8)
                }
                Circle()
                    .fill(recorder.state.color)
                    .frame(width: 12, height: 12)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(recorder.state.label)
                        .font(.headline)
                        .foregroundStyle(recorder.state.color)

                    if recorder.state == .recording {
                        Text(recorder.showMirrorWindow ? "· Window Mode" : "· Background Mode")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if recorder.state == .recording {
                    Text(recorder.liveAudioPlayback
                         ? "Recording video · Game sound is playing live through Mac"
                         : "Recording video · Muted on Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .finished(let url) = recorder.state {
                    Text("Saved to \(url.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .failed(let msg) = recorder.state {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    Text(recorder.showMirrorWindow
                         ? "Ready to record with live mirror window on Mac"
                         : "Ready to record in background (no mirror window)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Live metrics when recording
            if recorder.state == .recording {
                HStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text(recorder.elapsedFormatted)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Elapsed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 28)

                    VStack(spacing: 2) {
                        Text(recorder.fileSizeFormatted)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Reset button if finished or failed
            if case .finished = recorder.state {
                Button {
                    recorder.reset()
                } label: {
                    Label("New Recording", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            if case .failed = recorder.state {
                Button {
                    recorder.reset()
                } label: {
                    Label("Try Again", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(recorder.state == .recording ? Color.red.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(recorder.state == .recording ? Color.red.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Primary Action Card

    private var primaryActionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Big Start / Stop Button
                HStack(spacing: 12) {
                    if recorder.state.isActive {
                        Button(role: .destructive) {
                            recorder.stop()
                        } label: {
                            Label("Stop Recording", systemImage: "stop.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(recorder.state == .stopping)
                    } else {
                        Button {
                            recorder.start(serial: deviceSerial)
                        } label: {
                            Label("Start Screen Recording", systemImage: "record.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(deviceSerial.isEmpty)
                    }
                }

                if deviceSerial.isEmpty {
                    Label("No device selected. Please connect or select an Android device in the toolbar.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()

                // SHOW SCREEN WHILE RECORDING TOGGLE (User's primary requirement)
                Toggle(isOn: $recorder.showMirrorWindow) {
                    HStack(spacing: 10) {
                        Image(systemName: recorder.showMirrorWindow ? "macwindow" : "macwindow.badge.plus")
                            .font(.title2)
                            .foregroundStyle(recorder.showMirrorWindow ? .blue : .secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Screen on Mac While Recording")
                                .font(.subheadline.weight(.semibold))
                            Text(recorder.showMirrorWindow
                                 ? "A mirror window is displayed on Mac. You can view & control the phone while recording."
                                 : "Background recording mode: No window will appear on Mac. Video is saved directly to disk.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(recorder.state.isActive)

                Divider()

                // Quick Quality Presets & Format
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quality Preset:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Preset", selection: $recorder.qualityPreset) {
                            ForEach(RecordingQualityPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(recorder.state.isActive)
                        .onChange(of: recorder.qualityPreset) { preset in
                            recorder.applyPreset(preset)
                            if preset == .custom {
                                isFineTuningExpanded = true
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Format:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Picker("Format", selection: $recorder.recordingFormat) {
                            ForEach(RecordingFormat.allCases) { fmt in
                                Text(fmt.label).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        .disabled(recorder.state.isActive)
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Recording Controls", systemImage: "record.circle")
                .font(.headline)
        }
    }

    // MARK: - Sound Routing Card

    private var soundRoutingCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Live Game Sound on Mac Toggle
                Toggle(isOn: $recorder.liveAudioPlayback) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Hear Game Sound Live on Mac")
                                .font(.subheadline.weight(.medium))
                            Text("Plays game & device audio in real-time through your Mac speakers while recording.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(recorder.state.isActive)

                Divider()

                // Play Sound on Phone Speakers Too
                Toggle(isOn: $recorder.duplicateAudioToDevice) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.indigo)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Keep Sound on Phone Speakers Too")
                                .font(.subheadline.weight(.medium))
                            Text("Outputs audio to both phone and Mac speakers simultaneously (--audio-dup, Android 10+).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(recorder.state.isActive)

                Divider()

                // Include Sound Track in Video
                Toggle(isOn: $recorder.recordAudio) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.purple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Record Audio Track in Video File")
                                .font(.subheadline.weight(.medium))
                            Text("Embeds high-quality audio synchronized into the recorded video.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(recorder.state.isActive)
            }
            .padding(6)
        } label: {
            Label("Sound & Live Audio Routing", systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    // MARK: - Video Quality Fine-Tuning Card

    private var videoQualityCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Large full-width clickable toggle bar
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isFineTuningExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Video Quality Settings")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(isFineTuningExpanded ? "Collapse" : "Expand")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.blue.opacity(0.12)))
                                    .foregroundStyle(.blue)
                            }

                            Text(recorder.qualityPreset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isFineTuningExpanded ? 90 : 0))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(isHoveringQualityBar ? 0.06 : 0.02))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringQualityBar = hovering
                }

                if isFineTuningExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider().padding(.vertical, 6)

                        // Resolution Limit
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Max Resolution:")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(recorder.maxSize == 0 ? "Native (No downscale)" : "\(Int(recorder.maxSize)) px")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(recorder.maxSize == 0 ? .green : .primary)
                            }
                            Slider(value: $recorder.maxSize, in: 0...maxResolutionLimit, step: 120)
                                .disabled(recorder.state.isActive)
                                .onChange(of: recorder.maxSize) { _ in recorder.qualityPreset = .custom }

                            HStack(spacing: 6) {
                                chipButton("Native", active: recorder.maxSize == 0) { recorder.maxSize = 0 }
                                if maxResolutionLimit >= 1440 {
                                    chipButton("1440p", active: recorder.maxSize == 1440) { recorder.maxSize = 1440 }
                                }
                                if maxResolutionLimit >= 1080 {
                                    chipButton("1080p", active: recorder.maxSize == 1080) { recorder.maxSize = 1080 }
                                }
                                chipButton("720p", active: recorder.maxSize == 720) { recorder.maxSize = 720 }
                                chipButton("480p", active: recorder.maxSize == 480) { recorder.maxSize = 480 }
                                Spacer()
                            }
                        }

                        Divider()

                        // Frame Rate
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Max Frame Rate:")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(Int(recorder.maxFPS)) FPS")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            }
                            Slider(value: $recorder.maxFPS, in: 15...maxFPSLimit, step: 5)
                                .disabled(recorder.state.isActive)
                                .onChange(of: recorder.maxFPS) { _ in recorder.qualityPreset = .custom }

                            HStack(spacing: 6) {
                                chipButton("30 FPS", active: recorder.maxFPS == 30) { recorder.maxFPS = 30 }
                                chipButton("60 FPS", active: recorder.maxFPS == 60) { recorder.maxFPS = 60 }
                                if maxFPSLimit >= 90 {
                                    chipButton("90 FPS", active: recorder.maxFPS == 90) { recorder.maxFPS = 90 }
                                }
                                if maxFPSLimit >= 120 {
                                    chipButton("120 FPS", active: recorder.maxFPS == 120) { recorder.maxFPS = 120 }
                                }
                                Spacer()
                            }
                        }

                        Divider()

                        // Video Bitrate
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Video Bitrate:")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(Int(recorder.videoBitRate)) Mbps")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            }
                            Slider(value: $recorder.videoBitRate, in: 2...40, step: 1)
                                .disabled(recorder.state.isActive)
                                .onChange(of: recorder.videoBitRate) { _ in recorder.qualityPreset = .custom }

                            HStack(spacing: 6) {
                                chipButton("4M", active: recorder.videoBitRate == 4) { recorder.videoBitRate = 4 }
                                chipButton("8M", active: recorder.videoBitRate == 8) { recorder.videoBitRate = 8 }
                                chipButton("16M", active: recorder.videoBitRate == 16) { recorder.videoBitRate = 16 }
                                chipButton("24M", active: recorder.videoBitRate == 24) { recorder.videoBitRate = 24 }
                                chipButton("32M", active: recorder.videoBitRate == 32) { recorder.videoBitRate = 32 }
                                Spacer()
                            }
                        }

                        Divider()

                        // Video Codec
                        HStack {
                            Text("Video Codec:")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Picker("Codec", selection: $recorder.videoCodec) {
                                ForEach(VideoCodec.allCases) { codec in
                                    Text(codec.label).tag(codec)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220)
                            .disabled(recorder.state.isActive)
                            .onChange(of: recorder.videoCodec) { _ in recorder.qualityPreset = .custom }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(4)
        }
    }

    // MARK: - Destination Card

    private var destinationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(recorder.outputPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary.opacity(0.8))
                    Spacer()
                }

                HStack(spacing: 10) {
                    if !recorder.state.isActive {
                        Button("Choose Save Location…") {
                            chooseOutputPath()
                        }
                        .buttonStyle(.bordered)
                    }

                    if case .finished(let url) = recorder.state {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
            }
            .padding(6)
        } label: {
            Label("Save Destination", systemImage: "folder")
                .font(.headline)
        }
    }

    // MARK: - Helpers

    private func chipButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(label) {
            action()
            recorder.qualityPreset = .custom
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(active ? .blue : .secondary)
        .disabled(recorder.state.isActive)
    }

    private func chooseOutputPath() {
        let panel = NSSavePanel()
        panel.title = "Save Screen Recording As"
        panel.nameFieldStringValue = "recording.\(recorder.recordingFormat.rawValue)"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = recorder.recordingFormat == .mp4 ? [.mpeg4Movie] : [.movie]

        if panel.runModal() == .OK, let url = panel.url {
            recorder.outputPath = url.path
        }
    }
}

// MARK: - Backward Compatibility Typealias
typealias BackgroundRecordingView = ScreenRecordingView
