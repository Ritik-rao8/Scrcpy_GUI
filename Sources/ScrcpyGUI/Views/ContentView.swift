import SwiftUI
import AppKit

// MARK: - App Primary Section

enum AppSection: String, CaseIterable, Identifiable {
    case mirroring = "Screen Mirroring"
    case recording = "Screen Recording"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .mirroring: return "display"
        case .recording: return "record.circle"
        }
    }
}

// MARK: - Content View

/// The main application container.
/// Clearly splits the app into two dedicated sections:
///   1) Screen Mirroring Mode (viewing, interacting, sound, wireless)
///   2) Screen Recording Mode (windowed or headless, all quality presets, sound routing, destination)
struct ContentView: View {

    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var settings = ScrcpySettings()
    @StateObject private var commandRunner = CommandRunner()
    @StateObject private var screenRecorder = ScreenRecorder()

    @State private var activeSection: AppSection = .mirroring
    @State private var showConsole: Bool = true
    @State private var didCopyCommand: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Live Background Recording Banner (visible even if switched to Mirroring tab).
            if screenRecorder.state == .recording && activeSection == .mirroring {
                backgroundRecordingBanner
            }

            // Top Status Bar when Mirroring is Running.
            if commandRunner.isRunning && activeSection == .recording {
                mirroringRunningBanner
            }

            // Error banner if adb is missing or scan failed.
            if let error = deviceManager.lastError {
                errorBanner(error)
            }

            // Wireless status banner.
            if !deviceManager.wirelessStatus.isEmpty {
                wirelessBanner
            }

            // Primary Mode Selector (Mirroring vs Recording)
            primaryModeSelector
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)

            Divider()

            // Main Active Section Content
            ScrollView {
                VStack(spacing: 12) {
                    if activeSection == .mirroring {
                        SettingsView(
                            settings: settings,
                            deviceInfo: deviceManager.deviceInfo,
                            onSetupWireless: { serial in
                                deviceManager.setupWireless(serial: serial)
                            },
                            onConnectIP: { address in
                                deviceManager.connectWireless(address: address)
                            },
                            onDisconnectWireless: { serial in
                                deviceManager.disconnectWireless(serial: serial)
                            },
                            currentSerial: deviceManager.selectedDeviceSerial
                        )
                    } else {
                        ScreenRecordingView(
                            recorder: screenRecorder,
                            settings: settings,
                            deviceInfo: deviceManager.deviceInfo,
                            deviceSerial: deviceManager.selectedDeviceSerial
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }

            // Command Preview Bar with Copy button.
            commandPreviewBar

            Divider()

            // Console Panel (collapsible).
            if showConsole {
                ConsoleView(
                    text: activeSection == .mirroring ? commandRunner.consoleOutput : screenRecorder.consoleOutput,
                    onClear: {
                        if activeSection == .mirroring {
                            commandRunner.clearConsole()
                        } else {
                            screenRecorder.consoleOutput = ""
                        }
                    }
                )
                .frame(minHeight: 120, maxHeight: 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showConsole)
        .animation(.easeInOut(duration: 0.22), value: activeSection)
        .animation(.easeInOut(duration: 0.22), value: commandRunner.isRunning)
        .animation(.easeInOut(duration: 0.22), value: screenRecorder.state == .recording)
        .toolbar { toolbarContent }
        .frame(minWidth: 650, minHeight: 560)
        .onAppear { deviceManager.scanDevices() }
        // Re-fetch device info whenever the user picks a different device.
        .onChange(of: deviceManager.selectedDeviceSerial) { newSerial in
            if !newSerial.isEmpty {
                deviceManager.fetchDeviceInfo(serial: newSerial)
            } else {
                deviceManager.deviceInfo = nil
            }
        }
    }

    // MARK: - Mode Selector

    private var primaryModeSelector: some View {
        HStack {
            Picker("Mode", selection: $activeSection) {
                Label("Screen Mirroring", systemImage: "display")
                    .tag(AppSection.mirroring)

                HStack(spacing: 4) {
                    Label("Screen Recording", systemImage: "record.circle")
                    if screenRecorder.state == .recording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
                .tag(AppSection.recording)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Leading: Device picker + refresh.
        ToolbarItemGroup(placement: .navigation) {
            HStack(spacing: 6) {
                Image(systemName: "iphone.and.arrow.forward")
                    .foregroundStyle(.secondary)

                Picker("Device", selection: $deviceManager.selectedDeviceSerial) {
                    if deviceManager.devices.isEmpty {
                        Text("No devices found").tag("")
                    }
                    ForEach(deviceManager.devices) { device in
                        Text(device.displayName).tag(device.serial)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 180)

                Button {
                    deviceManager.scanDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(deviceManager.isScanning)
                .help("Refresh connected devices")
            }
        }

        // Trailing: Console toggle + Section-aware Start/Stop.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showConsole.toggle()
            } label: {
                Image(systemName: showConsole
                      ? "rectangle.bottomhalf.inset.filled"
                      : "rectangle.bottomhalf.filled")
            }
            .help(showConsole ? "Hide Console" : "Show Console")

            Divider()

            if activeSection == .mirroring {
                // Mirroring Start / Stop
                if commandRunner.isRunning {
                    Button(role: .destructive) {
                        commandRunner.stopScrcpy()
                    } label: {
                        Label("Stop Mirroring", systemImage: "stop.fill")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .help("Stop mirroring (⌘R)")
                } else {
                    Button {
                        startMirroring()
                    } label: {
                        Label("Start Mirroring", systemImage: "play.fill")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(deviceManager.selectedDevice == nil)
                    .help("Start mirroring (⌘R)")
                }
            } else {
                // Recording Start / Stop
                if screenRecorder.state.isActive {
                    Button(role: .destructive) {
                        screenRecorder.stop()
                    } label: {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .tint(.red)
                    .help("Stop recording (⌘R)")
                } else {
                    Button {
                        startRecording()
                    } label: {
                        Label("Start Recording", systemImage: "record.circle.fill")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(deviceManager.selectedDevice == nil)
                    .help("Start screen recording (⌘R)")
                }
            }
        }
    }

    // MARK: - Sub-views

    /// A pulsing red banner when recording is running in the background.
    private var backgroundRecordingBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("Recording Active  ·  \(screenRecorder.elapsedFormatted)  ·  \(screenRecorder.fileSizeFormatted)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.red)
            Spacer()
            Button("Switch to Recording") {
                activeSection = .recording
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .font(.callout.weight(.medium))
            Button("Stop") { screenRecorder.stop() }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.10))
    }

    /// A green banner shown while mirroring is running.
    private var mirroringRunningBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Mirroring is active on \(deviceManager.selectedDevice?.displayName ?? "device")…")
                .font(.callout.weight(.medium))
            Spacer()
            Button("Switch to Mirroring") {
                activeSection = .mirroring
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.green)
            .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.green.opacity(0.12))
        .foregroundStyle(.green)
    }

    /// A blue banner showing live wireless setup progress.
    private var wirelessBanner: some View {
        HStack(spacing: 8) {
            if deviceManager.isConfiguringWireless {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "wifi")
            }
            Text(deviceManager.wirelessStatus)
                .font(.callout.weight(.medium))
            Spacer()
            Button("Dismiss") { deviceManager.wirelessStatus = "" }
                .buttonStyle(.borderless)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.12))
        .foregroundStyle(.blue)
    }

    /// A red banner for errors.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.callout)
            Spacer()
            Button("Dismiss") { deviceManager.lastError = nil }
                .buttonStyle(.borderless)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red.opacity(0.12))
        .foregroundStyle(.red)
    }

    /// Command preview bar that dynamically shows the command for either Mirroring or Recording.
    private var commandPreviewBar: some View {
        let serial = deviceManager.selectedDeviceSerial.isEmpty
            ? "<device>"
            : deviceManager.selectedDeviceSerial

        let preview: String = {
            if activeSection == .mirroring {
                return settings.commandPreview(serial: serial, scrcpyPath: commandRunner.scrcpyPath)
            } else {
                return screenRecorder.commandPreview(serial: serial)
            }
        }()

        return HStack(spacing: 8) {
            Image(systemName: activeSection == .mirroring ? "display" : "record.circle")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(preview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(preview, forType: .string)
                didCopyCommand = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopyCommand = false
                }
            } label: {
                if didCopyCommand {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .help("Copy scrcpy command line")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35))
    }

    // MARK: - Actions

    private func startMirroring() {
        guard let device = deviceManager.selectedDevice else { return }
        let args = settings.buildArguments(serial: device.serial)
        commandRunner.startScrcpy(arguments: args)
    }

    private func startRecording() {
        guard let device = deviceManager.selectedDevice else { return }
        screenRecorder.start(serial: device.serial)
    }
}
