import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CategoryListView: View {
    let category: MustCategory
    @Binding var selectedItemID: UUID?

    @Environment(\.modelContext) private var context
    @Query private var items: [TodoItem]
    @State private var showAddSheet = false
    @State private var showCompleted = false
    @State private var urlInput = ""
    @State private var isDropTargeted = false

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
        VStack(spacing: 0) {
            if category != .mustDo {
                quickAddBar
                Divider()
            }
            listOrEmptyState
        }
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $showCompleted) {
                    Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)

                if category != .mustDo {
                    Button {
                        pickFiles()
                    } label: {
                        Label("Add File…", systemImage: "doc.badge.plus")
                    }
                    .help(filePickerHelp)
                }

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(category: category, onAdd: addItemFromSheet)
        }
    }

    @ViewBuilder private var listOrEmptyState: some View {
        if filteredItems.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(dropOverlay)
                .dropDestination(for: URL.self, action: { urls, _ in handleDrop(urls) }, isTargeted: { isDropTargeted = $0 })
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
            .background(dropOverlay)
            .dropDestination(for: URL.self, action: { urls, _ in handleDrop(urls) }, isTargeted: { isDropTargeted = $0 })
        }
    }

    @ViewBuilder private var dropOverlay: some View {
        if isDropTargeted && category != .mustDo {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .background(Color.accentColor.opacity(0.08))
                .padding(4)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No \(category.title) items")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(emptyStateHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if category != .mustDo {
                HStack {
                    Button {
                        pickFiles()
                    } label: {
                        Label("Choose File…", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("New Item", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)
            }
        }
    }

    private var emptyStateHint: String {
        switch category {
        case .mustDo:
            return "Press ⌘N or click + to add a todo."
        case .mustWatch:
            return "Paste a YouTube / Twitter / video URL in the bar above, drag video files here, or click + / Choose File."
        case .mustRead:
            return "Paste a web URL above, drag a PDF or EPUB here, or click + / Choose File."
        case .mustListen:
            return "Paste a podcast RSS or audio URL above, drag audio files here, or click + / Choose File."
        }
    }

    @ViewBuilder private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField(placeholderForQuickAdd, text: $urlInput)
                .textFieldStyle(.plain)
                .onSubmit { submitQuickAdd() }
            if !urlInput.isEmpty {
                Button("Add") { submitQuickAdd() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var placeholderForQuickAdd: String {
        switch category {
        case .mustWatch: return "Paste YouTube / Twitter / video URL…"
        case .mustRead: return "Paste a web URL…"
        case .mustListen: return "Paste podcast RSS or audio URL…"
        default: return ""
        }
    }

    private var filePickerHelp: String {
        switch category {
        case .mustWatch: return "Choose a video file"
        case .mustRead: return "Choose a PDF / EPUB / document"
        case .mustListen: return "Choose an audio file"
        default: return "Choose a file"
        }
    }

    private func submitQuickAdd() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }
        let item = TodoItem(category: category, title: trimmed, sourceURLString: trimmed)
        configureNewURLItem(item, url: url)
        context.insert(item)
        selectedItemID = item.id
        urlInput = ""
        Task { await enrichMetadata(for: item, url: url) }
    }

    private func addItemFromSheet(_ payload: AddItemSheet.Payload) {
        switch payload {
        case .text(let title, let notes):
            let item = TodoItem(category: category, title: title, notes: notes)
            context.insert(item)
            selectedItemID = item.id

        case .url(let title, let urlString):
            guard let url = URL(string: urlString) else { return }
            let item = TodoItem(
                category: category,
                title: title.isEmpty ? urlString : title,
                sourceURLString: urlString
            )
            configureNewURLItem(item, url: url)
            context.insert(item)
            selectedItemID = item.id
            Task { await enrichMetadata(for: item, url: url) }

        case .file(let title, let fileURL):
            do {
                let kind = MediaKind.detect(from: fileURL)
                let result = try MediaStore.shared.importFile(at: fileURL, preferredPrefix: category.rawValue)
                let item = TodoItem(
                    category: category,
                    title: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
                    storedFileName: result.storedName,
                    originalFileName: result.originalName
                )
                applyKind(category: category, kind: kind, to: item)
                context.insert(item)
                selectedItemID = item.id
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func configureNewURLItem(_ item: TodoItem, url: URL) {
        switch category {
        case .mustWatch:
            item.videoStatus = .pending
        case .mustRead:
            item.readKind = .webURL
        case .mustListen:
            item.listenKind = .podcastFeed
        default: break
        }
    }

    private func applyKind(category: MustCategory, kind: MediaKind, to item: TodoItem) {
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
    }

    private func enrichMetadata(for item: TodoItem, url: URL) async {
        let result = await MetadataFetcher.fetch(url: url)
        if let title = result.title, !title.isEmpty {
            await MainActor.run { item.title = title }
        }
        if category == .mustListen {
            await refreshPodcastFeed(for: item, url: url)
        }
        if category == .mustWatch {
            await fetchVideoInfo(for: item, url: url.absoluteString)
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

    @discardableResult
    private func handleDrop(_ urls: [URL]) -> Bool {
        guard category != .mustDo else { return false }
        for url in urls {
            importFile(at: url)
        }
        return !urls.isEmpty
    }

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
            applyKind(category: category, kind: kind, to: item)
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
            for url in panel.urls {
                importFile(at: url)
            }
        }
    }

    private var pickerContentTypes: [UTType] {
        switch category {
        case .mustWatch: return [.movie, .video, .audiovisualContent]
        case .mustRead: return [.pdf, .epub, .text, .rtf, UTType(filenameExtension: "mobi"), UTType(filenameExtension: "azw3"), UTType(filenameExtension: "azw")].compactMap { $0 }
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
