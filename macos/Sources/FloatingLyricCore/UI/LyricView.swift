import SwiftUI

public struct LyricView: View {
    @ObservedObject var model: LyricViewModel

    public init(model: LyricViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Once the panel fades the words sit straight on the desktop,
                // which could be anything. A soft shadow keeps them legible
                // against a light wallpaper without looking heavy on the blur.
                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            footer
        }
        // Extra headroom so the traffic-light buttons never sit on the text.
        .padding(EdgeInsets(top: 30, leading: 16, bottom: 16, trailing: 16))
        // Matches the window's own minimum; the window is resizable from here
        // up, and a wider one is what stops long lines from wrapping.
        .frame(minWidth: FloatingWindow.minimumSize.width,
               minHeight: FloatingWindow.minimumSize.height)
        // Hover is decided by the window (see `FloatingWindow.isPointerInside`),
        // not by SwiftUI: this window usually belongs to an inactive app.
        .contentShape(Rectangle())
    }

    /// Chrome fades out after a few idle seconds but keeps its space, so the
    /// lyrics never jump around as it comes and goes.
    private var chromeOpacity: Double { model.chromeVisible ? 1 : 0 }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 10))
            if let message = model.controlMessage {
                Text(message).lineLimit(1).foregroundStyle(.orange)
            } else {
                Text(model.title).fontWeight(.semibold).lineLimit(1)
                if !model.artist.isEmpty {
                    Text("— \(model.artist)").lineLimit(1)
                }
            }
            Spacer()
            if model.isOffline {
                Image(systemName: "wifi.slash").font(.system(size: 10))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .opacity(chromeOpacity)
        .animation(.easeInOut(duration: 0.25), value: model.chromeVisible)
    }

    @ViewBuilder
    private var content: some View {
        switch model.display {
        case .message(let text):
            Text(text)
                .font(.system(size: CGFloat(model.fontSize), weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: CGFloat(model.fontSize) - 2))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .synced(let document, let currentIndex):
            syncedLines(document: document, currentIndex: currentIndex)
        }
    }

    private func syncedLines(document: LyricsDocument, currentIndex: Int?) -> some View {
        let center = currentIndex ?? -1
        let window = Array((center - 1)...(center + 2))
        // Lines wrap rather than truncate, so four of them can outgrow a short
        // window. Scrolling keeps the overflow reachable, and the current line
        // is scrolled back into view whenever it changes.
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(window, id: \.self) { index in
                        if document.lines.indices.contains(index) {
                            line(document: document, index: index, isCurrent: index == center)
                                .id(index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentIndex) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(center, anchor: .center)
                }
            }
        }
    }

    private func line(document: LyricsDocument, index: Int, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(document.lines[index].text)
                .font(.system(size: CGFloat(model.fontSize),
                              weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.primary)
                                           : AnyShapeStyle(.tertiary))
            if model.showRomaji, let romaji = document.romanization(at: index) {
                Text(romaji)
                    .font(.system(size: max(9, CGFloat(model.fontSize) - 6)))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.secondary)
                                               : AnyShapeStyle(.quaternary))
            }
        }
        // No line limit anywhere above: a long line wraps onto as many lines as
        // it needs, and fixedSize stops SwiftUI compressing it back to one.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            transport
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
            HStack {
                Text(timecode(model.positionMs))
                Spacer()
                Text(timecode(model.durationMs))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .opacity(chromeOpacity)
        .animation(.easeInOut(duration: 0.25), value: model.chromeVisible)
    }

    private var transport: some View {
        HStack(spacing: 22) {
            transportButton("backward.fill", size: 12, help: "Previous track") {
                model.previousTapped()
            }
            transportButton(model.isPlaying ? "pause.fill" : "play.fill", size: 16,
                            help: model.isPlaying ? "Pause" : "Play") {
                model.playPauseTapped()
            }
            transportButton("forward.fill", size: 12, help: "Next track") {
                model.nextTapped()
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(!model.canControl)
        .opacity(model.canControl ? 1 : 0.35)
        // Hidden chrome must not swallow clicks aimed at the window behind it.
        .allowsHitTesting(model.chromeVisible)
    }

    private func transportButton(_ symbol: String, size: CGFloat, help: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var progressFraction: Double {
        guard model.durationMs > 0 else { return 0 }
        return min(1, Double(model.positionMs) / Double(model.durationMs))
    }

    private func timecode(_ ms: Int) -> String {
        let total = max(0, ms) / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
