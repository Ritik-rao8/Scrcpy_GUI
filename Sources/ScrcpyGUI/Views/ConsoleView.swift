import SwiftUI

/// A terminal-style view that displays live stdout/stderr output.
/// Features a dark background, monospaced font, copy, clear, and auto-scrolling.
struct ConsoleView: View {

    var text: String
    var onClear: (() -> Void)? = nil

    init(text: String, onClear: (() -> Void)? = nil) {
        self.text = text
        self.onClear = onClear
    }

    init(commandRunner: CommandRunner) {
        self.text = commandRunner.consoleOutput
        self.onClear = { commandRunner.clearConsole() }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar.
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.headline)

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy output")

                Button {
                    onClear?()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear console")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Terminal body.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        if text.isEmpty {
                            Text("Ready. Press Start to run…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        } else {
                            Text(text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.green)
                                .textSelection(.enabled)
                                .padding(10)
                        }

                        // Invisible anchor to scroll to.
                        Color.clear
                            .frame(height: 1)
                            .id("consoleBottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .onChange(of: text) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("consoleBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
