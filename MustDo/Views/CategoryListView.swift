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
    @State private var presentingAdd = false

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

                    Button {
                        presentingAdd = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $presentingAdd) {
                AddItemSheet(
                    initialCategory: category,
                    onPickedCategory: { _ in },
                    onItemAdded: { selectedItemID = $0 }
                )
            }
    }

    @ViewBuilder private var contentView: some View {
        if filteredItems.isEmpty {
            EmptyStateView(
                category: category,
                onAdd: { presentingAdd = true }
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

    // MARK: - File import (drag-and-drop directly onto the list)
    // We don't copy the file — store the absolute path so the player /
    // PDF view reads it in place.

    private func importFile(at url: URL) {
        let kind = MediaKind.detect(from: url)
        let item = TodoItem(
            category: category,
            title: url.deletingPathExtension().lastPathComponent,
            originalFileName: url.lastPathComponent
        )
        item.filePath = url.path
        switch (category, kind) {
        case (.mustWatch, .video): item.videoStatus = .downloaded
        case (.mustRead, .pdf): item.readKind = .pdf
        case (.mustRead, .epub): item.readKind = .epub
        case (.mustRead, .mobi): item.readKind = .mobi
        case (.mustRead, _): item.readKind = .otherFile
        case (.mustListen, .audio): item.listenKind = .audioFile
        default: break
        }
        context.insert(item)
        try? context.save()
        selectedItemID = item.id
    }

    private func toggleComplete(_ item: TodoItem) {
        item.completedAt = item.isCompleted ? nil : .now
        try? context.save()
    }

    private func delete(_ item: TodoItem) {
        if let name = item.storedFileName { MediaStore.shared.deleteFile(named: name) }
        if let name = item.thumbnailFileName { MediaStore.shared.deleteFile(named: name) }
        context.delete(item)
        try? context.save()
        if selectedItemID == item.id { selectedItemID = nil }
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
                loadFileURLs(from: providers) { urls in onURLs(urls) }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let category: MustCategory
    let onAdd: () -> Void

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

            Button(action: onAdd) {
                Label(addLabel, systemImage: "plus.circle.fill")
                    .frame(maxWidth: 260)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)

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
        case .mustWatch: return "Save YouTube, Twitter, or other video URLs to watch offline, or drop video files."
        case .mustRead: return "Save web articles, drop PDFs and EPUBs, or add other documents."
        case .mustListen: return "Subscribe to a podcast RSS feed, add an audio URL, or drop audio files."
        }
    }

    private var addLabel: String {
        switch category {
        case .mustDo: return "New Todo"
        case .mustWatch: return "New Must Watch"
        case .mustRead: return "New Must Read"
        case .mustListen: return "New Must Listen"
        }
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
                LinkText(text: item.title, strikethrough: item.isCompleted)
                    .lineLimit(2)
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
