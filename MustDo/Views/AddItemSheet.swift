import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Unified add sheet. Picks a type first, then shows the form for that type.
/// For media types (Watch / Read / Listen), the form has both a URL input
/// and a drag-and-drop area + file picker — so the user can add either way
/// without leaving the sheet.
struct AddItemSheet: View {
    let initialCategory: MustCategory
    let onPickedCategory: (MustCategory) -> Void
    let onItemAdded: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var category: MustCategory
    @State private var didSetInitial = false

    // Shared form state
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var urlInput: String = ""
    @State private var pendingFiles: [URL] = []
    @State private var isDropTargeted = false
    @State private var errorMessage: String?

    enum Field { case title, url }
    @FocusState private var focusedField: Field?

    /// The field a user most likely types into first for each category.
    private var primaryField: Field {
        category == .mustDo ? .title : .url
    }

    init(initialCategory: MustCategory, onPickedCategory: @escaping (MustCategory) -> Void, onItemAdded: @escaping (UUID) -> Void) {
        self.initialCategory = initialCategory
        self.onPickedCategory = onPickedCategory
        self.onItemAdded = onItemAdded
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Type", selection: $category) {
                        ForEach(MustCategory.allCases) { c in
                            Label(c.title, systemImage: c.systemImage).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: category) { _, new in
                        onPickedCategory(new)
                        // Reset transient form state when switching type so old
                        // pendingFiles/url don't get sent to a new category.
                        pendingFiles.removeAll()
                        errorMessage = nil
                        // Move the cursor to the new form's primary field.
                        DispatchQueue.main.async { focusedField = primaryField }
                    }

                    Group {
                        switch category {
                        case .mustDo: mustDoForm
                        case .mustWatch: mediaForm(urlKind: .watchVideo)
                        case .mustRead: mediaForm(urlKind: .readWeb)
                        case .mustListen: listenForm
                        }
                    }

                    if let err = errorMessage {
                        Text(err).foregroundStyle(.red).font(.callout)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .onAppear {
            // Focus the primary field once the sheet is on screen.
            DispatchQueue.main.async { focusedField = primaryField }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: category.systemImage)
                .foregroundStyle(.tint)
                .font(.title3)
            Text("New \(category.title) item")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add") { performAdd() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Forms

    private var mustDoForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Title")
            TextField("What needs doing?", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)

            sectionHeader("Notes")
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
        }
    }

    @ViewBuilder
    private func mediaForm(urlKind: URLKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Title (optional)")
            TextField("Auto-filled from the page or file name", text: $title)
                .textFieldStyle(.roundedBorder)

            sectionHeader(urlKind.headline)
            HStack(spacing: 8) {
                TextField(urlKind.placeholder, text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .url)
                    .onSubmit { if canSubmitURL { performAdd() } }
            }
            Text(urlKind.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                Text("OR").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            }

            sectionHeader(category == .mustWatch ? "Video Files"
                          : category == .mustRead ? "Documents"
                          : "Audio Files")
            DropArea(
                category: category,
                isTargeted: $isDropTargeted,
                onPicked: { urls in
                    for u in urls where !pendingFiles.contains(u) {
                        pendingFiles.append(u)
                    }
                }
            )
            .frame(height: 120)

            if !pendingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pendingFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                pendingFiles.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var listenForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Title (optional)")
            TextField("Auto-filled from feed or file", text: $title)
                .textFieldStyle(.roundedBorder)

            sectionHeader("Podcast RSS or Audio URL")
            TextField("https://…", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .url)
                .onSubmit { if canSubmitURL { performAdd() } }
            Text("RSS feeds are parsed into a playable episode list. Other audio URLs are played directly with AVPlayer.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                Text("OR").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            }

            sectionHeader("Audio Files")
            DropArea(
                category: .mustListen,
                isTargeted: $isDropTargeted,
                onPicked: { urls in
                    for u in urls where !pendingFiles.contains(u) {
                        pendingFiles.append(u)
                    }
                }
            )
            .frame(height: 120)

            if !pendingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pendingFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                pendingFiles.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Submission

    private var canAdd: Bool {
        switch category {
        case .mustDo:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .mustWatch, .mustRead, .mustListen:
            return canSubmitURL || !pendingFiles.isEmpty
        }
    }

    private var canSubmitURL: Bool {
        let s = urlInput.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return URL(string: s) != nil
    }

    private func performAdd() {
        switch category {
        case .mustDo:
            let item = TodoItem(category: .mustDo, title: title, notes: notes)
            context.insert(item)
            onItemAdded(item.id)
            dismiss()

        case .mustWatch, .mustRead, .mustListen:
            var lastID: UUID?
            if canSubmitURL {
                let trimmed = urlInput.trimmingCharacters(in: .whitespaces)
                if let url = URL(string: trimmed) {
                    let item = makeURLItem(category: category, urlString: trimmed, title: title)
                    context.insert(item)
                    lastID = item.id
                    Task { await enrichURLItem(item, url: url) }
                }
            }
            for fileURL in pendingFiles {
                let item = makeFileItem(category: category, fileURL: fileURL, title: title)
                context.insert(item)
                lastID = item.id
            }
            if let lastID { onItemAdded(lastID) }
            dismiss()
        }
    }

    private func makeURLItem(category: MustCategory, urlString: String, title: String) -> TodoItem {
        let item = TodoItem(
            category: category,
            title: title.isEmpty ? urlString : title,
            sourceURLString: urlString
        )
        switch category {
        case .mustWatch:
            item.videoStatus = .pending
        case .mustRead:
            item.readKind = .webURL
        case .mustListen:
            // Heuristic: try as podcast feed first; refresh will demote to .audioURL on parse failure.
            item.listenKind = .podcastFeed
        default: break
        }
        return item
    }

    private func makeFileItem(category: MustCategory, fileURL: URL, title: String) -> TodoItem {
        let kind = MediaKind.detect(from: fileURL)
        let item = TodoItem(
            category: category,
            title: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
            originalFileName: fileURL.lastPathComponent
        )
        item.filePath = fileURL.path
        switch (category, kind) {
        case (.mustWatch, .video): item.videoStatus = .downloaded
        case (.mustRead, .pdf): item.readKind = .pdf
        case (.mustRead, .epub): item.readKind = .epub
        case (.mustRead, .mobi): item.readKind = .mobi
        case (.mustRead, _): item.readKind = .otherFile
        case (.mustListen, .audio): item.listenKind = .audioFile
        default: break
        }
        return item
    }

    private func enrichURLItem(_ item: TodoItem, url: URL) async {
        let meta = await MetadataFetcher.fetch(url: url)
        if let t = meta.title, !t.isEmpty {
            await MainActor.run { item.title = t }
        }
        if item.category == .mustListen {
            if let feed = try? await RSSParser.fetch(from: url) {
                await MainActor.run {
                    if !feed.title.isEmpty { item.title = feed.title }
                    item.notes = feed.description
                    item.listenKind = .podcastFeed
                    item.lastFeedRefreshAt = .now
                    item.episodes?.removeAll()
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
            } else {
                await MainActor.run { item.listenKind = .audioURL }
            }
        }
        if item.category == .mustWatch, YTDLPService.shared.isAvailable,
           let info = try? await YTDLPService.shared.fetchInfo(url: url.absoluteString) {
            await MainActor.run {
                if let t = info.title { item.title = t }
                if let d = info.duration { item.durationSeconds = d }
            }
        }
    }
}

// MARK: - URLKind metadata

enum URLKind {
    case watchVideo, readWeb

    var headline: String {
        switch self {
        case .watchVideo: return "YouTube / Twitter / Video URL"
        case .readWeb: return "Web Page URL"
        }
    }
    var placeholder: String {
        switch self {
        case .watchVideo: return "https://www.youtube.com/watch?v=…"
        case .readWeb: return "https://…"
        }
    }
    var hint: String {
        switch self {
        case .watchVideo: return "The video will be downloaded for offline playback with bundled yt-dlp."
        case .readWeb: return "Opens inside MustDo in an embedded browser view."
        }
    }
}

// MARK: - DropArea

struct DropArea: View {
    let category: MustCategory
    @Binding var isTargeted: Bool
    let onPicked: ([URL]) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                )
            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "square.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(isTargeted ? "Release to add" : promptText)
                    .font(.callout)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Button("Browse…") { browse() }
                    .controlSize(.small)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { browse() }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            loadFileURLs(from: providers) { urls in
                onPicked(urls)
            }
        }
    }

    private var promptText: String {
        switch category {
        case .mustWatch: return "Drop video files here, or click to browse"
        case .mustRead: return "Drop PDF / EPUB / documents here, or click to browse"
        case .mustListen: return "Drop audio files here, or click to browse"
        default: return "Drop files here, or click to browse"
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = pickerTypes(for: category)
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            onPicked(panel.urls)
        }
    }
}

private func pickerTypes(for category: MustCategory) -> [UTType] {
    switch category {
    case .mustWatch: return [.movie, .video, .audiovisualContent]
    case .mustRead:
        return [
            .pdf, .epub, .text, .rtf,
            UTType(filenameExtension: "mobi"),
            UTType(filenameExtension: "azw3"),
            UTType(filenameExtension: "azw")
        ].compactMap { $0 }
    case .mustListen: return [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
    default: return []
    }
}

@discardableResult
func loadFileURLs(from providers: [NSItemProvider], _ onURLs: @escaping ([URL]) -> Void) -> Bool {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    var any = false
    for provider in providers {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
        any = true
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            var url: URL?
            if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) {
                url = u
            } else if let u = item as? URL {
                url = u
            } else if let s = item as? String, let u = URL(string: s) {
                url = u
            }
            if let u = url {
                lock.lock(); urls.append(u); lock.unlock()
            }
        }
    }
    group.notify(queue: .main) {
        if !urls.isEmpty { onURLs(urls) }
    }
    return any
}
