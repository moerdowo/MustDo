import SwiftUI

struct TextItemSheet: View {
    let category: MustCategory
    let onAdd: (_ title: String, _ notes: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: category.systemImage).foregroundStyle(.tint)
                Text("New \(category.title)").font(.headline)
                Spacer()
            }
            Form {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(title, notes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct URLItemSheet: View {
    enum URLKind {
        case watchVideo
        case readWeb
        case listenPodcast
        case listenAudioURL
    }

    let kind: URLKind
    let onAdd: (_ urlString: String, _ title: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""
    @State private var title: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon).foregroundStyle(.tint)
                Text(heading).font(.headline)
                Spacer()
            }
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField(placeholder, text: $urlInput)
                TextField("Title (optional, auto-filled on add)", text: $title)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let trimmed = urlInput.trimmingCharacters(in: .whitespaces)
                    onAdd(trimmed, title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private var canSubmit: Bool {
        let s = urlInput.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && URL(string: s) != nil
    }

    private var icon: String {
        switch kind {
        case .watchVideo: return "play.rectangle.fill"
        case .readWeb: return "globe"
        case .listenPodcast: return "dot.radiowaves.left.and.right"
        case .listenAudioURL: return "link"
        }
    }

    private var heading: String {
        switch kind {
        case .watchVideo: return "Add Video URL"
        case .readWeb: return "Add Web Page"
        case .listenPodcast: return "Add Podcast Feed"
        case .listenAudioURL: return "Add Audio URL"
        }
    }

    private var placeholder: String {
        switch kind {
        case .watchVideo: return "YouTube, Twitter, Vimeo, or direct video URL"
        case .readWeb: return "https://…"
        case .listenPodcast: return "Podcast RSS / Atom feed URL"
        case .listenAudioURL: return "Direct audio file URL"
        }
    }

    private var hint: String {
        switch kind {
        case .watchVideo: return "The video will be downloaded for offline playback using bundled yt-dlp."
        case .readWeb: return "Opens inside MustDo in an embedded browser view."
        case .listenPodcast: return "The RSS feed is parsed into a playable episode list."
        case .listenAudioURL: return "Played directly with AVPlayer when selected."
        }
    }
}
