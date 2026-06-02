import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CategoryListView: View {
    let category: MustCategory
    @Binding var selectedItemID: UUID?

    @Environment(\.modelContext) private var context
    @Query private var items: [TodoItem]
    @State private var showCompleted = false
    @State private var isDropTargeted = false

    @State private var presentingTextSheet = false
    @State private var presentingURLSheet: URLItemSheet.URLKind?

    init(category: MustCategory, selectedItemID: Binding<UUID?>) {
        self.category = category
        self._selectedItemID = selectedItemID
        let raw = category.rawValue
        let predicate = #Predicate<TodoItem> { item in
            item.categoryRaw == raw
        }
        self._items = Query(filter: predicate, sort: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    var filteredItems: [TodoItem] {
        items.filter { showCompleted || !$0.isCompleted }
    }

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .applyDrop(
                category: category,
                isTargeted: $isDropTargeted,
                onURLs: { urls in
                    for u in urls { importFile(at: u) }
                }
            )
            .overlay {
                if isDropTargeted && category != .mustDo {
                    dropOverlay
                }
            }
            .navigationTitle(category.title)
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $showCompleted) {
                        Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash")
                    }
                    .toggleStyle(.button)

                    addMenuToolbarItem
                }
            }
            .sheet(isPresented: $presentingTextSheet) {
                TextItemSheet(category: category) { title, notes in
                    let item = TodoItem(
                        category: category,
                        title: title.isEmpty ? "Untitled" : title,
                        notes: notes
                    )
                    context.insert(item)
                    selectedItemID = item.id
                }
            }
            .sheet(item: $presentingURLSheet) { kind in
                URLItemSheet(kind: kind) { urlString, title in
                    addURLItem(kind: kind, urlString: urlString, title: title)
                }
            }
    }

    @ViewBuilder private var contentView: some View {
        if filteredItems.isEmpty {
            EmptyStateView(
                category: category,
                onTextAdd: { presentingTextSheet = true },
                onURLAdd: { presentingURLSheet = $0 },
                onFilePick: pickFiles
            )
        } else {
            List(selection: $selectedItemID) {
                ForEach(filteredItems, id: \.id) { item in
                    ItemRow(item: item)
                        .tag(item.id as UUID?)
                        .contextMenu {
                            Button(item.isCompleted ? "Mark Not Done" : "Mark Done") {
                                toggleComplete(item)
                            }
                            Divider()
                            Button("Delete", role: .destructive) { delete(item) }
                        }
                }
                .onDelete { offsets in
                    for index in offsets {
                        delete(filteredItems[index])
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.15))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 3)
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 36))
                Text("Drop to add to \(category.title)")
                    .font(.headline)
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(8)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var addMenuToolbarItem: some View {
        switch category {
        case .mustDo:
            Button {
                presentingTextSheet = true
            } label: {
                Label("New Todo", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)

        case .mustWatch:
            Menu {
                Button {
                    presentingURLSheet = .watchVideo
                } label: { Label("Paste Video URL…", systemImage: "link") }
                Button {
                    pickFiles()
                } label: { Label("Add Video File…", systemImage: "film") }
            } label: {
                Label("Add", systemImage: "plus")
            }

        case .mustRead:
            Menu {
                Button {
                    presentingURLSheet = .readWeb
                } label: { Label("Paste Web URL…", systemImage: "globe") }
                Button {
                    pickFiles()
                } label: { Label("Add PDF / EPUB / Doc…", systemImage: "doc.text") }
            } label: {
                Label("Add", systemImage: "plus")
            }

        case .mustListen:
            Menu {
                Button {
                    presentingURLSheet = .listenPodcast
                } label: { Label("Add Podcast Feed…", systemImage: "dot.radiowaves.left.and.right") }
                Button {
                    presentingURLSheet = .listenAudioURL
                } label: { Label("Paste Audio URL…", systemImage: "link") }
                Button {
                    pickFiles()
                } label: { Label("Add Audio File…", systemImage: "music.note") }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    // MARK: - Add logic

    private func addURLItem(kind: URLItemSheet.URLKind, urlString: String, title: String) {
        guard let url = URL(string: urlString) else { return }
        let item = TodoItem(
            category: category,
            title: title.isEmpty ? urlString : title,
            sourceURLString: urlString
        )
        switch kind {
        case .watchVideo:
            item.videoStatus = .pending
        case .readWeb:
            item.readKind = .webURL
        case .listenPodcast:
            item.listenKind = .podcastFeed
        case .listenAudioURL:
            item.listenKind = .audioURL
        }
        context.insert(item)
        selectedItemID = item.id
        Task { await enrichMetadata(for: item, url: url, kind: kind) }
    }

    private func enrichMetadata(for item: TodoItem, url: URL, kind: URLItemSheet.URLKind) async {
        let meta = await MetadataFetcher.fetch(url: url)
        if let title = meta.title, !title.isEmpty {
            await MainActor.run { item.title = title }
        }
        switch kind {
        case .listenPodcast:
            await refreshPodcastFeed(for: item, url: url)
        case .watchVideo:
            await fetchVideoInfo(for: item, url: url.absoluteString)
        default: break
        }
    }

    private func refreshPodcastFeed(for item: TodoItem, url: URL) async {
        do {
            let feed = try await RSSParser.fetch(from: url)
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
        } catch {
            await MainActor.run {
                item.listenKind = .audioURL
            }
        }
    }

    private func fetchVideoInfo(for item: TodoItem, url: String) async {
        guard YTDLPService.shared.isAvailable else { return }
        if let info = try? await YTDLPService.shared.fetchInfo(url: url) {
            await MainActor.run {
                if let t = info.title { item.title = t }
                if let d = info.duration { item.durationSeconds = d }
            }
        }
    }

    // MARK: - File import

    private func importFile(at url: URL) {
        do {
            let kind = MediaKind.detect(from: url)
            let result = try MediaStore.shared.importFile(at: url, preferredPrefix: category.rawValue)
            let item = TodoItem(
                category: category,
                title: url.deletingPathExtension().lastPathComponent,
                storedFileName: result.storedName,
                originalFileName: result.originalName
            )
            switch (category, kind) {
            case (.mustWatch, .video):
                item.videoStatus = .downloaded
            case (.mustRead, .pdf):
                item.readKind = .pdf
            case (.mustRead, .epub):
                item.readKind = .epub
            case (.mustRead, .mobi):
                item.readKind = .mobi
            case (.mustRead, _):
                item.readKind = .otherFile
            case (.mustListen, .audio):
                item.listenKind = .audioFile
            default: break
            }
            context.insert(item)
            selectedItemID = item.id
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = pickerContentTypes
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            for url in panel.urls { importFile(at: url) }
        }
    }

    private var pickerContentTypes: [UTType] {
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

    private func toggleComplete(_ item: TodoItem) {
        item.completedAt = item.isCompleted ? nil : .now
    }

    private func delete(_ item: TodoItem) {
        if let name = item.storedFileName { MediaStore.shared.deleteFile(named: name) }
        if let name = item.thumbnailFileName { MediaStore.shared.deleteFile(named: name) }
        context.delete(item)
        if selectedItemID == item.id { selectedItemID = nil }
    }
}

// MARK: - URLItemSheet selection wrapper

extension URLItemSheet.URLKind: Identifiable {
    public var id: String {
        switch self {
        case .watchVideo: return "watchVideo"
        case .readWeb: return "readWeb"
        case .listenPodcast: return "listenPodcast"
        case .listenAudioURL: return "listenAudioURL"
        }
    }
}

// MARK: - Drop modifier

private extension View {
    @ViewBuilder
    func applyDrop(
        category: MustCategory,
        isTargeted: Binding<Bool>,
        onURLs: @escaping ([URL]) -> Void
    ) -> some View {
        if category == .mustDo {
            self
        } else {
            self.onDrop(of: [UTType.fileURL], isTargeted: isTargeted) { providers in
                loadURLs(from: providers, onURLs: onURLs)
            }
        }
    }
}

private func loadURLs(from providers: [NSItemProvider], onURLs: @escaping ([URL]) -> Void) -> Bool {
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
            if let url {
                lock.lock(); urls.append(url); lock.unlock()
            }
        }
    }
    group.notify(queue: .main) {
        if !urls.isEmpty { onURLs(urls) }
    }
    return any
}

// MARK: - Empty state

struct EmptyStateView: View {
    let category: MustCategory
    let onTextAdd: () -> Void
    let onURLAdd: (URLItemSheet.URLKind) -> Void
    let onFilePick: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: category.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(headline)
                .font(.title2.bold())
            Text(subhead)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            VStack(spacing: 10) {
                buttons
            }
            .padding(.top, 6)

            if category != .mustDo {
                Text("Tip: you can also drag files from Finder onto this list.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headline: String {
        switch category {
        case .mustDo: return "Nothing on your todo list"
        case .mustWatch: return "Nothing to watch yet"
        case .mustRead: return "Nothing to read yet"
        case .mustListen: return "Nothing to listen to yet"
        }
    }

    private var subhead: String {
        switch category {
        case .mustDo: return "Add tasks you want to get done."
        case .mustWatch: return "Save YouTube, Twitter, or other video URLs to watch offline, or add local video files."
        case .mustRead: return "Save web articles, drop in PDFs and EPUBs, or add other documents."
        case .mustListen: return "Subscribe to a podcast feed, add an audio URL, or import local audio files."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch category {
        case .mustDo:
            primaryButton("New Todo", icon: "square.and.pencil", action: onTextAdd)

        case .mustWatch:
            primaryButton("Paste Video URL…", icon: "link") { onURLAdd(.watchVideo) }
            secondaryButton("Add Video File…", icon: "film", action: onFilePick)

        case .mustRead:
            primaryButton("Paste Web URL…", icon: "globe") { onURLAdd(.readWeb) }
            secondaryButton("Add PDF / EPUB / Doc…", icon: "doc.text", action: onFilePick)

        case .mustListen:
            primaryButton("Add Podcast Feed…", icon: "dot.radiowaves.left.and.right") { onURLAdd(.listenPodcast) }
            secondaryButton("Paste Audio URL…", icon: "link") { onURLAdd(.listenAudioURL) }
            secondaryButton("Add Audio File…", icon: "music.note", action: onFilePick)
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: 260)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: 260)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }
}

// MARK: - Row

struct ItemRow: View {
    @Bindable var item: TodoItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                item.completedAt = item.isCompleted ? nil : .now
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(2)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            statusBadge
        }
        .padding(.vertical, 4)
    }

    private var subtitleText: String? {
        if let url = item.sourceURL { return url.host ?? url.absoluteString }
        if let orig = item.originalFileName { return orig }
        if !item.notes.isEmpty { return item.notes }
        return nil
    }

    @ViewBuilder private var statusBadge: some View {
        switch item.category {
        case .mustWatch:
            switch item.videoStatus {
            case .pending: Text("queued").font(.caption2).foregroundStyle(.secondary)
            case .downloading:
                if let p = item.videoProgress {
                    Text("\(Int(p*100))%").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.mini)
                }
            case .downloaded: Image(systemName: "play.circle.fill").foregroundStyle(.tertiary)
            case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            case .notApplicable: EmptyView()
            }
        case .mustListen:
            if item.listenKind == .podcastFeed, let count = item.episodes?.count, count > 0 {
                Text("\(count) ep").font(.caption2).foregroundStyle(.secondary)
            }
        default: EmptyView()
        }
    }
}
