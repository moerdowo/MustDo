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
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $showCompleted) {
                    Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(category: category) { newItem in
                context.insert(newItem)
                selectedItemID = newItem.id
            }
        }
        .onDrop(of: dropTypes, isTargeted: nil) { providers in
            handleDrop(providers: providers)
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
        .padding(8)
    }

    private var placeholderForQuickAdd: String {
        switch category {
        case .mustWatch: return "Paste YouTube / Twitter / video URL…"
        case .mustRead: return "Paste a web URL…"
        case .mustListen: return "Paste podcast RSS or audio URL…"
        default: return ""
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

    private func configureNewURLItem(_ item: TodoItem, url: URL) {
        switch category {
        case .mustWatch:
            item.videoStatus = .pending
        case .mustRead:
            item.readKind = .webURL
        case .mustListen:
            // Heuristic: treat as podcast feed first; if parsing fails it's just an audio URL.
            item.listenKind = .podcastFeed
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

    private var dropTypes: [UTType] {
        switch category {
        case .mustDo: return []
        case .mustWatch: return [.fileURL, .movie, .video]
        case .mustRead: return [.fileURL, .pdf, .epub]
        case .mustListen: return [.fileURL, .audio]
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard category != .mustDo else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in importFile(at: url) }
                }
            }
        }
        return handled
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
