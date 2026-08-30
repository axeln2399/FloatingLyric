import AppKit
import SwiftUI

@MainActor
public final class SetupWindow: NSWindowController {
    public let prompt: LoginPrompt

    public init(prompt: LoginPrompt = .firstRun, onSave: @escaping (String) -> Void) {
        self.prompt = prompt
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = prompt == .firstRun ? "Set up FloatingLyric" : "Log in to Spotify"
        window.center()
        super.init(window: window)

        let view = SetupView(prompt: prompt,
                             initialClientID: Defaults.clientID ?? "") { [weak self] clientID in
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
    private let prompt: LoginPrompt
    @State private var clientID: String
    /// Only ever opened by hand, from the log-in screen: the Client ID is
    /// already right, and re-showing the whole walkthrough would be noise.
    @State private var isEditingClientID: Bool
    private let onSave: (String) -> Void

    init(prompt: LoginPrompt, initialClientID: String, onSave: @escaping (String) -> Void) {
        self.prompt = prompt
        _clientID = State(initialValue: initialClientID)
        _isEditingClientID = State(initialValue: prompt == .firstRun)
        self.onSave = onSave
    }

    private var trimmedClientID: String {
        clientID.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if prompt == .firstRun {
                Text("Connect your Spotify account").font(.title2.bold())
                walkthrough
            } else {
                Text("You're logged out").font(.title2.bold())
                Text("""
                     Log in again to start following what you're playing. Your \
                     browser will open Spotify's page once — click Agree, and \
                     you can close the tab.
                     """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isEditingClientID {
                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                Button("Use a different Client ID…") { isEditingClientID = true }
                    .buttonStyle(.link)
                    .padding(.leading, -4)
            }

            HStack {
                Link("Open Spotify Dashboard",
                     destination: URL(string: "https://developer.spotify.com/dashboard")!)
                Spacer()
                Button(prompt == .firstRun ? "Save and Log In" : "Log In with Spotify") {
                    onSave(trimmedClientID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedClientID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var walkthrough: some View {
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
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}
