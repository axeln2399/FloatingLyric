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
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            footer
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 180)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 10))
            Text(model.title).fontWeight(.semibold).lineLimit(1)
            if !model.artist.isEmpty {
                Text("— \(model.artist)").lineLimit(1)
            }
            Spacer()
            if model.isOffline {
                Image(systemName: "wifi.slash").font(.system(size: 10))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        switch model.display {
        case .message(let text):
            Text(text)
                .font(.system(size: CGFloat(model.fontSize), weight: .medium))
                .foregroundStyle(.secondary)
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
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(window, id: \.self) { index in
                if document.lines.indices.contains(index) {
                    Text(document.lines[index].text)
                        .font(.system(size: CGFloat(model.fontSize),
                                      weight: index == center ? .bold : .regular))
                        .foregroundStyle(index == center ? AnyShapeStyle(.primary)
                                                         : AnyShapeStyle(.tertiary))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    private var footer: some View {
        VStack(spacing: 4) {
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
