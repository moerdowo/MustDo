import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedCategory: MustCategory? = .mustDo
    @State private var selectedItemID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } content: {
            if let category = selectedCategory {
                CategoryListView(category: category, selectedItemID: $selectedItemID)
                    .id(category)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            } else {
                ContentUnavailableView("Select a list", systemImage: "sidebar.left")
            }
        } detail: {
            DetailHost(itemID: selectedItemID)
        }
        .navigationTitle("MustDo")
    }
}

struct SidebarView: View {
    @Binding var selection: MustCategory?
    @Query private var items: [TodoItem]

    var body: some View {
        List(selection: $selection) {
            Section("Lists") {
                ForEach(MustCategory.allCases) { c in
                    Label {
                        HStack {
                            Text(c.title)
                            Spacer()
                            Text("\(count(for: c))")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospacedDigit())
                        }
                    } icon: {
                        Image(systemName: c.systemImage)
                    }
                    .tag(c as MustCategory?)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func count(for c: MustCategory) -> Int {
        items.filter { $0.category == c && !$0.isCompleted }.count
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
