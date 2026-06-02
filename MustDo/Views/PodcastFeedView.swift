import SwiftUI
import AVKit

struct PodcastFeedView: View {
    @Bindable var item: TodoItem
    let refresh: () async -> Void

    @State private var selectedEpisodeID: UUID?
    @State private var isRefreshing = false

    var sortedEpisodes: [PodcastEpisode] {
        (item.episodes ?? []).sorted {
            ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
        }
    }

    var selectedEpisode: PodcastEpisode? {
        guard let id = selectedEpisodeID else { return sortedEpisodes.first }
        return sortedEpisodes.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("\(sortedEpisodes.count) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task {
                            isRefreshing = true
                            await refresh()
                            isRefreshing = false
                        }
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
                Divider()
                List(selection: $selectedEpisodeID) {
                    ForEach(sortedEpisodes, id: \.id) { ep in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ep.title).lineLimit(2)
                            if let d = ep.publishedAt {
                                Text(d, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(ep.id as UUID?)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300)

            if let ep = selectedEpisode {
                EpisodeDetailView(episode: ep)
            } else {
                ContentUnavailableView("No episode", systemImage: "music.note.list")
            }
        }
    }
}

struct EpisodeDetailView: View {
    @Bindable var episode: PodcastEpisode

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(episode.title).font(.title3.bold())
                if let d = episode.publishedAt {
                    Text(d, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                if !episode.summary.isEmpty {
                    ScrollView {
                        Text(stripHTML(episode.summary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            if let url = episode.audioURL {
                AudioPlayerView(url: url)
                    .frame(maxHeight: 240)
            } else {
                Text("No audio enclosure")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func stripHTML(_ s: String) -> String {
        var out = s
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: (out as NSString).length)
            out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "")
        }
        return out
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
