import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedCategory: MustCategory? = .mustDo
    @State private var selectedItemID: UUID?
    @State private var showAddSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedCategory,
                onAdd: { showAddSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            if let category = selectedCategory {
                CategoryListView(category: category, selectedItemID: $selectedItemID)
                    .id(category)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360)
            } else {
                ContentUnavailableView("Select a list", systemImage: "sidebar.left")
            }
        } detail: {
            DetailHost(itemID: selectedItemID)
        }
        .navigationTitle("MustDo")
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(
                initialCategory: selectedCategory ?? .mustDo,
                onPickedCategory: { selectedCategory = $0 },
                onItemAdded: { selectedItemID = $0 }
            )
        }
    }
}

struct SidebarView: View {
    @Binding var selection: MustCategory?
    let onAdd: () -> Void
    @Query private var items: [TodoItem]

    var body: some View {
        List(selection: $selection) {
            Section("Lists") {
                ForEach(MustCategory.allCases) { c in
                    SidebarRow(category: c, count: count(for: c))
                        .tag(c as MustCategory?)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    onAdd()
                } label: {
                    Label("New Item", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: .command)
                .help("Add a new item to any list")
            }
            .background(.bar)
        }
    }

    private func count(for c: MustCategory) -> Int {
        items.filter { $0.category == c && !$0.isCompleted }.count
    }
}

struct SidebarRow: View {
    let category: MustCategory
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(category.title)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.callout.monospacedDigit())
            }
        }
        .contentShape(Rectangle())
    }
}

struct DetailHost: View {
    let itemID: UUID?
    @Query private var items: [TodoItem]

    var body: some View {
        if let id = itemID, let item = items.first(where: { $0.id == id }) {
            ItemDetailView(item: item)
                .id(id)
        } else {
            ContentUnavailableView("No selection", systemImage: "doc.text", description: Text("Pick an item from the list."))
        }
    }
}
