import SwiftUI
import SwiftData

/// Combined view of every list. Items from all four categories in one
/// place, newest first, each tagged with its category.
struct AllItemsView: View {
    @Binding var selectedItemID: UUID?
    let onAdd: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TodoItem.createdAt, order: .reverse)])
    private var items: [TodoItem]
    @State private var showCompleted = false

    private var visibleItems: [TodoItem] {
        items.filter { showCompleted || !$0.isCompleted }
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "tray.full")
                } description: {
                    Text("Add items to any list and they'll all show up here.")
                } actions: {
                    Button {
                        onAdd()
                    } label: {
                        Label("New Item", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedItemID) {
                    ForEach(visibleItems, id: \.id) { item in
                        ItemRow(item: item)
                            .tag(item.id as UUID?)
                            .contextMenu {
                                Button(item.isCompleted ? "Mark Not Done" : "Mark Done") {
                                    item.completedAt = item.isCompleted ? nil : .now
                                    try? context.save()
                                }
                                Divider()
                                Button("Delete", role: .destructive) { delete(item) }
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets { delete(visibleItems[index]) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("All Must Do")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $showCompleted) {
                    Label("Show Completed", systemImage: showCompleted ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)

                Button {
                    onAdd()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    private func delete(_ item: TodoItem) {
        if let name = item.storedFileName { MediaStore.shared.deleteFile(named: name) }
        if let name = item.thumbnailFileName { MediaStore.shared.deleteFile(named: name) }
        context.delete(item)
        try? context.save()
        if selectedItemID == item.id { selectedItemID = nil }
    }
}
