import SwiftUI
import SwiftData

/// Sidebar selection: the combined "All" view, or one specific list.
enum SidebarItem: Hashable {
    case all
    case category(MustCategory)
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .all
    @State private var selectedItemID: UUID?
    @State private var showAddSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                onAdd: { showAddSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            Group {
                switch selection {
                case .all:
                    AllItemsView(selectedItemID: $selectedItemID, onAdd: { showAddSheet = true })
                case .category(let category):
                    CategoryListView(category: category, selectedItemID: $selectedItemID)
                        .id(category)
                case nil:
                    ContentUnavailableView("Select a list", systemImage: "sidebar.left")
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            DetailHost(itemID: selectedItemID)
        }
        .navigationTitle("MustDo")
        .focusEffectDisabled()
        .sheet(isPresented: $showAddSheet) {
            AddItemSheet(
                initialCategory: defaultAddCategory,
                onPickedCategory: { selection = .category($0) },
                onItemAdded: { selectedItemID = $0 }
            )
        }
    }

    private var defaultAddCategory: MustCategory {
        if case .category(let c) = selection { return c }
        return .mustDo
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let onAdd: () -> Void
    @Query private var items: [TodoItem]

    var body: some View {
        List(selection: $selection) {
            Section {
                SidebarRowView(
                    title: "All Must Do",
                    systemImage: "tray.full.fill",
                    count: totalIncomplete
                )
                .tag(SidebarItem.all)
            }
            Section("Lists") {
                ForEach(MustCategory.allCases) { c in
                    SidebarRowView(
                        title: c.title,
                        systemImage: c.systemImage,
                        count: count(for: c)
                    )
                    .tag(SidebarItem.category(c))
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

    private var totalIncomplete: Int {
        items.filter { !$0.isCompleted }.count
    }

    private func count(for c: MustCategory) -> Int {
        items.filter { $0.category == c && !$0.isCompleted }.count
    }
}

struct SidebarRowView: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(title)
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
