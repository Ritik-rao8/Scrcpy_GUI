import SwiftUI
import AppKit

// MARK: - Mirroring Settings Category Tabs

enum MirroringCategory: String, CaseIterable, Identifiable {
    case display = "Display"
    case audio = "Audio"
    case device = "Device & Window"
    case wireless = "Wireless Setup"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .display:  return "display"
        case .audio:    return "speaker.wave.2"
        case .device:   return "iphone"
        case .wireless: return "wifi"
        }
    }
}

// MARK: - Settings View (Screen Mirroring)

/// A clean, organized settings panel for Screen Mirroring.
/// Categorized into fast, non-congested tabs: Display, Audio, Device & Window, and Wireless.
struct SettingsView: View {

    @ObservedObject var settings: ScrcpySettings
    var deviceInfo: DeviceInfo?
    var onSetupWireless: ((String) -> Void)? = nil
    var currentSerial: String = ""

    @State private var activeCategory: MirroringCategory = .display

    /// Dynamic upper bound for the resolution slider.
    private var maxResolution: Double {
        Double(deviceInfo?.maxDimension ?? 2560)
    }

    /// Dynamic upper bound for the FPS slider.
    private var maxRefreshRate: Double {
        deviceInfo?.refreshRate ?? 120
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Detected Device Capabilities Pill Strip.
            if let info = deviceInfo {
                deviceCapabilitiesPill(info)
            }

            // Category Segmented Tab Bar.
            Picker("Category", selection: $activeCategory) {
                ForEach(MirroringCategory.allCases) { cat in
                    Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 2)

            // Active Tab Content Area.
            tabContent
                .padding(.top, 4)
        }
        .onChange(of: deviceInfo) { newInfo in
            guard let info = newInfo else { return }
            let maxRes = Double(info.maxDimension)
            if settings.maxSize > maxRes {
                settings.maxSize = maxRes
            }
            if settings.maxFPS > info.refreshRate {
                settings.maxFPS = info.refreshRate
            }
        }
    }

    // MARK: - Device Pill

    private func deviceCapabilitiesPill(_ info: DeviceInfo) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("Detected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Divider().frame(height: 12)

            Label("\(info.screenWidth) × \(info.screenHeight)", systemImage: "rectangle.ratio.16.to.9")
            Divider().frame(height: 12)
            Label("\(Int(info.refreshRate)) Hz", systemImage: "bolt.fill")

            if !info.androidVersion.isEmpty {
                Divider().frame(height: 12)
                Label("Android \(info.androidVersion)", systemImage: "cpu")
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    // MARK: - Tab Router

    @ViewBuilder
    private var tabContent: some View {
        switch activeCategory {
        case .display:
            displayTab
        case .audio:
            audioTab
        case .device:
            deviceWindowTab
        case .wireless:
            wirelessTab
        }
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Resolution
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max Resolution:")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(settings.maxSize == 0 ? "Native (No downscale)" : "\(Int(settings.maxSize)) px")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(settings.maxSize == 0 ? .green : .primary)
                    }
                    Slider(value: $settings.maxSize, in: 0...maxResolution, step: 120)

                    HStack(spacing: 6) {
                        presetChip("Native", value: 0, current: settings.maxSize) { settings.maxSize = 0 }
                        if maxResolution >= 1440 {
                            presetChip("1440p", value: 1440, current: settings.maxSize) { settings.maxSize = 1440 }
                        }
                        if maxResolution >= 1080 {
                            presetChip("1080p", value: 1080, current: settings.maxSize) { settings.maxSize = 1080 }
                        }
                        presetChip("720p", value: 720, current: settings.maxSize) { settings.maxSize = 720 }
                        presetChip("480p", value: 480, current: settings.maxSize) { settings.maxSize = 480 }
                        Spacer()
                    }
                }

                Divider()

                // Max FPS
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max Frame Rate:")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(settings.maxFPS)) FPS")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    }
                    Slider(value: $settings.maxFPS, in: 15...maxRefreshRate, step: 5)

                    HStack(spacing: 6) {
                        presetChip("30 FPS", value: 30, current: settings.maxFPS) { settings.maxFPS = 30 }
                        presetChip("60 FPS", value: 60, current: settings.maxFPS) { settings.maxFPS = 60 }
                        if maxRefreshRate >= 90 {
                            presetChip("90 FPS", value: 90, current: settings.maxFPS) { settings.maxFPS = 90 }
                        }
                        if maxRefreshRate >= 120 {
                            presetChip("120 FPS", value: 120, current: settings.maxFPS) { settings.maxFPS = 120 }
                        }
                        Spacer()
                    }
                }

                Divider()

                // Bitrate
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Video Bitrate:")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(settings.videoBitRate)) Mbps")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    }
                    Slider(value: $settings.videoBitRate, in: 2...40, step: 1)

                    HStack(spacing: 6) {
                        presetChip("4M", value: 4, current: settings.videoBitRate) { settings.videoBitRate = 4 }
                        presetChip("8M", value: 8, current: settings.videoBitRate) { settings.videoBitRate = 8 }
                        presetChip("16M", value: 16, current: settings.videoBitRate) { settings.videoBitRate = 16 }
                        presetChip("24M", value: 24, current: settings.videoBitRate) { settings.videoBitRate = 24 }
                        presetChip("32M", value: 32, current: settings.videoBitRate) { settings.videoBitRate = 32 }
                        Spacer()
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Display Quality", systemImage: "display")
                .font(.headline)
        }
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.noAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disable Audio Forwarding")
                            .font(.subheadline.weight(.medium))
                        Text("Mute all sound from the phone on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if !settings.noAudio {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Audio Bitrate:")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(Int(settings.audioBitRate)) Kbps")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        }
                        Slider(value: $settings.audioBitRate, in: 32...320, step: 16)

                        HStack(spacing: 6) {
                            presetChip("64K", value: 64, current: settings.audioBitRate) { settings.audioBitRate = 64 }
                            presetChip("128K", value: 128, current: settings.audioBitRate) { settings.audioBitRate = 128 }
                            presetChip("192K", value: 192, current: settings.audioBitRate) { settings.audioBitRate = 192 }
                            presetChip("256K", value: 256, current: settings.audioBitRate) { settings.audioBitRate = 256 }
                            Spacer()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Audio Buffer Delay:")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(settings.audioBufferMs == 0 ? "0 ms (Default)" : "\(Int(settings.audioBufferMs)) ms")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        }
                        Slider(value: $settings.audioBufferMs, in: 0...200, step: 5)
                        Text("Adds buffer latency to reduce stutter on Wi-Fi. Keep at 0 for USB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            presetChip("0 ms (USB)", value: 0, current: settings.audioBufferMs) { settings.audioBufferMs = 0 }
                            presetChip("50 ms", value: 50, current: settings.audioBufferMs) { settings.audioBufferMs = 50 }
                            presetChip("100 ms (Wi-Fi)", value: 100, current: settings.audioBufferMs) { settings.audioBufferMs = 100 }
                            Spacer()
                        }
                    }
                }
            }
            .padding(6)
        } label: {
            Label("Sound & Audio Forwarding", systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    // MARK: - Device & Window Tab

    private var deviceWindowTab: some View {
        VStack(spacing: 14) {
            // Device options
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Turn Screen Off While Mirroring", isOn: $settings.turnScreenOff)
                    Toggle("Stay Awake (Don't sleep when plugged in)", isOn: $settings.stayAwake)
                    Toggle("Show Touch Feedback Dots", isOn: $settings.showTouches)
                    Toggle("View Only Mode (Disable keyboard & mouse input)", isOn: $settings.noControl)
                }
                .toggleStyle(.checkbox)
                .padding(6)
            } label: {
                Label("Device Behavior", systemImage: "iphone")
                    .font(.headline)
            }

            // Window options
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Always on Top", isOn: $settings.alwaysOnTop)
                    Toggle("Launch in Fullscreen", isOn: $settings.fullscreen)
                    Toggle("Borderless Window", isOn: $settings.borderless)

                    HStack {
                        Text("Window Title:")
                            .font(.subheadline)
                        TextField("e.g. My Phone", text: $settings.windowTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(6)
            } label: {
                Label("Window Appearance", systemImage: "macwindow")
                    .font(.headline)
            }
        }
    }

    // MARK: - Wireless Tab

    private var wirelessTab: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Switch your USB-connected device to Wi-Fi mode to unplug the cable and mirror wirelessly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "cable.connector.slash")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step 1: Keep USB cable connected")
                            .font(.caption.weight(.semibold))
                        Text("Click the button below to enable TCP/IP mode and discover device IP.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "wifi")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step 2: Unplug cable & enjoy")
                            .font(.caption.weight(.semibold))
                        Text("Once connected wirelessly, you can unplug the USB cable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Button {
                    guard !currentSerial.isEmpty else { return }
                    onSetupWireless?(currentSerial)
                } label: {
                    Label("Switch to Wi-Fi Mode", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(currentSerial.isEmpty)
                .help(currentSerial.isEmpty
                      ? "Connect a device via USB first"
                      : "Enable wireless mode on \(currentSerial)")
            }
            .padding(6)
        } label: {
            Label("Wireless Setup Tool", systemImage: "wifi")
                .font(.headline)
        }
    }

    // MARK: - Preset Chip Helper

    private func presetChip(_ label: String, value: Double, current: Double, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(current == value ? .blue : .secondary)
    }
}
