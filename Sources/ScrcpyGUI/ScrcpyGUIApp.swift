import SwiftUI
import AppKit

// MARK: - App Delegate for Dock Icon

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setDockIcon()
    }

    private func setDockIcon() {
        // Try loading from app bundle resources
        if let bundleImage = Bundle.main.image(forResource: "AppIcon") {
            NSApplication.shared.applicationIconImage = bundleImage
            return
        }

        // Try loading from local Resources during development
        let possiblePaths = [
            "Resources/AppIcon.png",
            "Resources/AppIcon.icns",
            "../Resources/AppIcon.png"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path) {
                NSApplication.shared.applicationIconImage = image
                return
            }
        }
    }
}

// MARK: - App Main

@main
struct ScrcpyGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 720, height: 700)
    }
}
