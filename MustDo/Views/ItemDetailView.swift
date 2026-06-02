import SwiftUI
import SwiftData
import AVKit

struct ItemDetailView: View {
    @Bindable var item: TodoItem
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                item.completedAt = item.isCompleted ? nil : .now
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                if let url = item.sourceURL {
                    Link(destination: url) {
                        Label(url.absoluteString, systemImage: "link")
                            .lineLimit(1)
                            .font(.callout)
                    }
                }
                if let orig = item.originalFileName {
                    Text(orig)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder private var content: some View {
        switch item.category {
        case .mustDo:
            MustDoContent(item: item)
        case .mustWatch:
            MustWatchContent(item: item)
        case .mustRead:
            MustReadContent(item: item)
        case .mustListen:
            MustListenContent(item: item)
        }
    }
}

struct MustDoContent: View {
    @Bindable var item: TodoItem
    var body: some View {
        TextEditor(text: $item.notes)
            .font(.body)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
    }
}

struct MustWatchContent: View {
    @Bindable var item: TodoItem
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            if let localURL = item.storedFileURL, item.videoStatus == .downloaded {
                VideoPlayer(player: AVPlayer(url: localURL))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let urlString = item.sourceURLString {
                downloadPanel(urlString: urlString)
            } else {
                ContentUnavailableView("No video", systemImage: "play.slash")
            }
        }
        .padding()
    }

    @ViewBuilder
    private func downloadPanel(urlString: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(urlString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            switch item.videoStatus {
            case .pending, .notApplicable, .failed:
                if !YTDLPService.shared.isAvailable {
                    Text("yt-dlp is not bundled. Run scripts/fetch_ytdlp.sh and rebuild.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await startDownload(urlString: urlString) }
                } label: {
                    Label("Download for offline", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!YTDLPService.shared.isAvailable)
                if item.videoStatus == .failed, let e = error ?? item.notes.nonEmpty {
                    Text(e).font(.caption).foregroundStyle(.red).lineLimit(4)
                }
            case .downloading:
                VStack(spacing: 8) {
                    if let p = item.videoProgress {
                        ProgressView(value: p)
                            .frame(maxWidth: 300)
                        Text("\(Int(p*100))%").monospacedDigit()
                    } else {
                        ProgressView()
                    }
                }
            case .downloaded:
                EmptyView()
            }
            if let e = error {
                Text(e).foregroundStyle(.red).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startDownload(urlString: String) async {
        item.videoStatus = .downloading
        item.videoProgress = nil
        error = nil
        do {
            let result = try await YTDLPService.shared.download(url: urlString) { p in
                item.videoProgress = p
            }
            item.storedFileName = result.videoName
            item.thumbnailFileName = result.thumbnailName
            item.videoStatus = .downloaded
            item.videoProgress = 1.0
        } catch {
            item.videoStatus = .failed
            self.error = (error as NSError).localizedDescription
        }
    }
}

struct MustReadContent: View {
    @Bindable var item: TodoItem

    var body: some View {
        Group {
            switch item.readKind {
            case .pdf:
                if let url = item.storedFileURL {
                    PDFReaderView(url: url)
                } else {
                    ContentUnavailableView("Missing PDF", systemImage: "doc")
                }
            case .epub:
                if let url = item.storedFileURL {
                    EPUBReaderView(epubURL: url)
                } else {
                    ContentUnavailableView("Missing EPUB", systemImage: "book")
                }
            case .mobi, .otherFile:
                FileFallbackView(item: item)
            case .webURL:
                if let url = item.sourceURL {
                    WebPageView(url: url)
                } else {
                    ContentUnavailableView("Missing URL", systemImage: "link")
                }
            case .none:
                Text("Add a web URL or drop a PDF / EPUB.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileFallbackView: View {
    let item: TodoItem
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(item.originalFileName ?? "File")
            HStack {
                if let url = item.storedFileURL {
                    Button("Open in Default App") { NSWorkspace.shared.open(url) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MustListenContent: View {
    @Bindable var item: TodoItem
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            switch item.listenKind {
            case .audioFile:
                if let url = item.storedFileURL {
                    AudioPlayerView(url: url)
                } else {
                    ContentUnavailableView("Missing audio", systemImage: "music.note")
                }
            case .audioURL:
                if let url = item.sourceURL {
                    AudioPlayerView(url: url)
                } else {
                    ContentUnavailableView("Missing URL", systemImage: "link")
                }
            case .podcastFeed:
                PodcastFeedView(item: item, refresh: refreshFeed)
            case .none:
                ContentUnavailableView("No audio", systemImage: "music.note.list")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshFeed() async {
        guard let url = item.sourceURL else { return }
        do {
            let feed = try await RSSParser.fetch(from: url)
            await MainActor.run {
                if !feed.title.isEmpty { item.title = feed.title }
                item.notes = feed.description
                item.lastFeedRefreshAt = .now
                // Replace episodes
                if let existing = item.episodes {
                    for e in existing { context.delete(e) }
                }
                for (i, ep) in feed.episodes.enumerated() {
                    let episode = PodcastEpisode(
                        title: ep.title,
                        summary: ep.summary,
                        publishedAt: ep.publishedAt,
                        audioURLString: ep.audioURL,
                        durationSeconds: ep.durationSeconds,
                        sortOrder: Double(i)
                    )
                    episode.parent = item
                    context.insert(episode)
                }
            }
        } catch {
            // ignore; fall back to plain URL
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
