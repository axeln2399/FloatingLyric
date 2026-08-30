import AppKit
import SwiftUI

@MainActor
public final class SetupWindow: NSWindowController {
    public init(onSave: @escaping (String) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Set up FloatingLyric"
        window.center()
        super.init(window: window)

        let view = SetupView(initialClientID: Defaults.clientID ?? "") { [weak self] clientID in
            onSave(clientID)
            self?.close()
        }
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public override func close() {
        super.close()
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct SetupView: View {
    @State private var clientID: String
    private let onSave: (String) -> Void

    init(initialClientID: String, onSave: @escaping (String) -> Void) {
        _clientID = State(initialValue: initialClientID)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your Spotify account").font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open developer.spotify.com/dashboard and click Create app.")
                step(2, "Name it anything, e.g. FloatingLyric.")
                step(3, "Set the Redirect URI to exactly:")
                Text("http://127.0.0.1:8888/callback")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 5))
                step(4, "Tick \"Web API\", save, then copy the Client ID below.")
            }
            .font(.callout)

            TextField("Client ID", text: $clientID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Link("Open Spotify Dashboard",
                     destination: URL(string: "https://developer.spotify.com/dashboard")!)
                Spacer()
                Button("Save and Log In") {
                    onSave(clientID.trimmingCharacters(in: .whitespaces))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}
