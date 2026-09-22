import Foundation
import SwiftUI

// MARK: - Device Info

/// Hardware capabilities detected from a connected Android device.
/// Used to set dynamic slider ranges in the settings UI.
struct DeviceInfo: Equatable {
    let screenWidth: Int
    let screenHeight: Int
    let refreshRate: Double
    let androidVersion: String

    /// The larger screen dimension (used for --max-size upper bound).
    var maxDimension: Int { max(screenWidth, screenHeight) }

    /// Fallback values when no device is connected.
    static let defaults = DeviceInfo(
        screenWidth: 1080,
        screenHeight: 1920,
        refreshRate: 60,
        androidVersion: ""
    )
}

// MARK: - ADB Device

/// Represents a single Android device detected by `adb devices -l`.
struct ADBDevice: Identifiable, Hashable {
    let id: String          // same as serial
    let serial: String
    let status: String      // "device", "unauthorized", etc.
    let model: String       // parsed from `model:` field, fallback to serial
    let transportId: String // parsed from `transport_id:` field

    /// A user-friendly display name.
    var displayName: String {
        if model != serial {
            return "\(model)  (\(serial))"
        }
        return serial
    }
}

// MARK: - Device Manager

/// Scans for connected Android devices using `adb` and publishes them to the UI.
class DeviceManager: ObservableObject {

    @Published var devices: [ADBDevice] = []
    @Published var selectedDeviceSerial: String = ""
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    @Published var deviceInfo: DeviceInfo?
    @Published var isFetchingInfo: Bool = false

    /// Resolved path to the `adb` binary.
    var adbPath: String {
        PathResolver.find("adb") ?? "/opt/homebrew/bin/adb"
    }

    /// The currently-selected device, if any.
    var selectedDevice: ADBDevice? {
        devices.first { $0.serial == selectedDeviceSerial }
    }

    // MARK: Scanning

    func scanDevices() {
        isScanning = true
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let resolvedPath = self.adbPath
            guard FileManager.default.isExecutableFile(atPath: resolvedPath) else {
                DispatchQueue.main.async {
                    self.lastError = "adb not found. Install it via: brew install android-platform-tools"
                    self.devices = []
                    self.isScanning = false
                }
                return
            }

            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: resolvedPath)
            process.arguments = ["devices", "-l"]
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ["PATH": PathResolver.combinedPATH]

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                let parsed = self.parseDevices(output)

                DispatchQueue.main.async {
                    self.devices = parsed

                    // Keep selection if still valid, otherwise pick first.
                    let previousSerial = self.selectedDeviceSerial
                    if !parsed.contains(where: { $0.serial == previousSerial }) {
                        self.selectedDeviceSerial = parsed.first?.serial ?? ""
                    }
                    self.isScanning = false

                    // Auto-fetch device info for the selected device.
                    if !self.selectedDeviceSerial.isEmpty {
                        self.fetchDeviceInfo(serial: self.selectedDeviceSerial)
                    } else {
                        self.deviceInfo = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "Failed to run adb: \(error.localizedDescription)"
                    self.devices = []
                    self.isScanning = false
                }
            }
        }
    }

    // MARK: Wireless Setup

    @Published var wirelessStatus: String = ""
    @Published var isConfiguringWireless: Bool = false

    /// Enables TCP/IP mode on the USB-connected device, discovers its IP,
    /// and connects to it over Wi-Fi — all in the background.
    func setupWireless(serial: String) {
        isConfiguringWireless = true
        wirelessStatus = "Enabling TCP/IP mode on port 5555…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Step 1: adb -s <serial> tcpip 5555
            _ = self.runADB(["-s", serial, "tcpip", "5555"])
            DispatchQueue.main.async {
                self.wirelessStatus = "TCP/IP enabled. Discovering device IP…"
            }

            // Brief pause to let the device restart its adbd in TCP mode.
            Thread.sleep(forTimeInterval: 1.5)

            // Step 2: grab the device's Wi-Fi IP address with multi-strategy fallback
            let ip = self.discoverDeviceIP(serial: serial)

            guard let deviceIP = ip, !deviceIP.isEmpty else {
                DispatchQueue.main.async {
                    self.wirelessStatus = ""
                    self.lastError = "Could not auto-detect Wi-Fi IP address. Please ensure phone is connected to the same Wi-Fi as your Mac, or enter the IP manually."
                    self.isConfiguringWireless = false
                }
                return
            }

            let address = "\(deviceIP):5555"
            DispatchQueue.main.async {
                self.wirelessStatus = "Connecting to \(address)…"
            }

            // Step 3: Warm up network route (populates Mac ARP cache for device)
            self.warmUpNetworkRoute(ip: deviceIP)

            // Step 4: adb connect <ip>:5555 with auto-recovery retry
            var connectOut = self.runADB(["connect", address]) ?? ""
            if !connectOut.contains("connected") {
                // If stale ADB server has a cached socket error, restart server and retry
                _ = self.runADB(["kill-server"])
                _ = self.runADB(["start-server"])
                Thread.sleep(forTimeInterval: 1.2)
                connectOut = self.runADB(["connect", address]) ?? ""
            }

            DispatchQueue.main.async {
                self.isConfiguringWireless = false
                if connectOut.contains("connected") {
                    self.wirelessStatus = "✓ Connected to \(address). You can unplug the USB cable now!"
                    // Select the newly connected wireless device
                    self.selectedDeviceSerial = address
                    // Refresh the device list so the new Wi-Fi serial appears.
                    self.scanDevices()
                } else {
                    self.wirelessStatus = ""
                    self.lastError = "adb connect failed: \(connectOut)"
                }
            }
        }
    }

    /// Connect directly to a device over Wi-Fi via IP and port.
    func connectWireless(address: String) {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let target = clean.contains(":") ? clean : "\(clean):5555"
        let ipOnly = target.components(separatedBy: ":").first ?? target

        isConfiguringWireless = true
        wirelessStatus = "Connecting to \(target)…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.warmUpNetworkRoute(ip: ipOnly)

            var out = self.runADB(["connect", target]) ?? ""
            if !out.contains("connected") {
                // Auto-retry with fresh server in case of stale sockets
                _ = self.runADB(["kill-server"])
                _ = self.runADB(["start-server"])
                Thread.sleep(forTimeInterval: 1.2)
                out = self.runADB(["connect", target]) ?? ""
            }

            DispatchQueue.main.async {
                self.isConfiguringWireless = false
                if out.contains("connected") {
                    self.wirelessStatus = "✓ Successfully connected to \(target)!"
                    self.selectedDeviceSerial = target
                    self.scanDevices()
                } else {
                    self.wirelessStatus = ""
                    self.lastError = "Connection failed: \(out)"
                }
            }
        }
    }

    /// Disconnects a wireless ADB session.
    func disconnectWireless(serial: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.runADB(["disconnect", serial])
            DispatchQueue.main.async {
                self.wirelessStatus = "Disconnected from \(serial)"
                self.scanDevices()
            }
        }
    }

    /// Pings the target IP once to resolve ARP and prime the network route on macOS.
    private func warmUpNetworkRoute(ip: String) {
        let pingProcess = Process()
        pingProcess.executableURL = URL(fileURLWithPath: "/sbin/ping")
        pingProcess.arguments = ["-c", "1", "-t", "1", ip]
        pingProcess.standardOutput = FileHandle.nullDevice
        pingProcess.standardError = FileHandle.nullDevice
        try? pingProcess.run()
        pingProcess.waitUntilExit()
    }

    /// Attempts multiple strategies to find the device's local Wi-Fi IP address.
    private func discoverDeviceIP(serial: String) -> String? {
        // Strategy A: ip -f inet addr show wlan0
        if let out = self.runADB(["-s", serial, "shell", "ip", "-f", "inet", "addr", "show", "wlan0"]),
           let ip = extractFirstInetIP(from: out) {
            return ip
        }

        // Strategy B: any non-loopback inet from `ip -f inet addr`
        if let out = self.runADB(["-s", serial, "shell", "ip", "-f", "inet", "addr"]),
           let ip = extractFirstInetIP(from: out) {
            return ip
        }

        // Strategy C: getprop dhcp.wlan0.ipaddress
        if let prop = self.runADB(["-s", serial, "shell", "getprop", "dhcp.wlan0.ipaddress"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prop.isEmpty && isValidIPv4(prop) {
            return prop
        }

        return nil
    }

    private func extractFirstInetIP(from output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let withoutInet = trimmed.dropFirst(5)
                let tokens = withoutInet.split(separator: " ")
                if let firstToken = tokens.first {
                    let ipCandidate = String(firstToken.split(separator: "/").first ?? "")
                    if isValidIPv4(ipCandidate) && ipCandidate != "127.0.0.1" {
                        return ipCandidate
                    }
                }
            }
        }
        return nil
    }

    private func isValidIPv4(_ str: String) -> Bool {
        let parts = str.split(separator: ".")
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let num = Int(part), (0...255).contains(num) else { return false }
        }
        return true
    }

    // MARK: Device Info

    /// Queries the connected device for its screen resolution, refresh rate,
    /// and Android version so the UI can adapt slider ranges dynamically.
    func fetchDeviceInfo(serial: String) {
        isFetchingInfo = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // --- Screen Resolution ---
            var width = 1080, height = 1920
            if let wmOutput = self.runADB(["-s", serial, "shell", "wm", "size"]) {
                for line in wmOutput.components(separatedBy: "\n") {
                    if line.contains("Physical size:") {
                        let parts = line.components(separatedBy: ": ")
                        if let sizeStr = parts.last {
                            let dims = sizeStr.components(separatedBy: "x")
                            if dims.count == 2,
                               let w = Int(dims[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                               let h = Int(dims[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                                width = w
                                height = h
                            }
                        }
                    }
                }
            }

            // --- Refresh Rate ---
            var refreshRate: Double = 60

            // Attempt 1: query the system setting for peak refresh rate.
            if let peakStr = self.runADB(["-s", serial, "shell", "settings", "get", "system", "peak_refresh_rate"]),
               let rate = Double(peakStr), rate > 0 {
                refreshRate = rate
            } else {
                // Attempt 2: parse `dumpsys display` for the highest reported refreshRate.
                if let dumpOutput = self.runADB(["-s", serial, "shell", "dumpsys", "display"]) {
                    if let regex = try? NSRegularExpression(pattern: "refreshRate=(\\d+\\.?\\d*)") {
                        let nsStr = dumpOutput as NSString
                        let matches = regex.matches(in: dumpOutput, range: NSRange(location: 0, length: nsStr.length))
                        for match in matches {
                            if match.numberOfRanges >= 2 {
                                let rateStr = nsStr.substring(with: match.range(at: 1))
                                if let rate = Double(rateStr), rate > refreshRate {
                                    refreshRate = rate
                                }
                            }
                        }
                    }
                }
            }

            // --- Android Version ---
            let androidVersion = self.runADB(["-s", serial, "shell", "getprop", "ro.build.version.release"]) ?? ""

            let info = DeviceInfo(
                screenWidth: width,
                screenHeight: height,
                refreshRate: refreshRate,
                androidVersion: androidVersion
            )

            DispatchQueue.main.async {
                self.deviceInfo = info
                self.isFetchingInfo = false
            }
        }
    }

    // MARK: ADB Helper

    /// Runs a single `adb` command synchronously and returns its trimmed stdout.
    private func runADB(_ arguments: [String]) -> String? {
        let resolvedPath = adbPath
        guard FileManager.default.isExecutableFile(atPath: resolvedPath) else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = ["PATH": PathResolver.combinedPATH]

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: Parsing

    private func parseDevices(_ output: String) -> [ADBDevice] {
        var result: [ADBDevice] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip header and empty lines.
            if trimmed.isEmpty || trimmed.hasPrefix("List of") || trimmed.hasPrefix("*") {
                continue
            }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let status = parts[1]

            guard status == "device" || status == "unauthorized" else { continue }

            // Extract optional metadata fields.
            var model = serial
            var transportId = ""

            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") {
                    model = String(part.dropFirst(6))
                } else if part.hasPrefix("transport_id:") {
                    transportId = String(part.dropFirst(13))
                }
            }

            result.append(ADBDevice(
                id: serial,
                serial: serial,
                status: status,
                model: model,
                transportId: transportId
            ))
        }

        return result
    }
}
