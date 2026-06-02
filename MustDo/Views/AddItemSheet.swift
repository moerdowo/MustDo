import SwiftUI

struct AddItemSheet: View {
    let category: MustCategory
    let onAdd: (TodoItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: category.systemImage)
                Text("New \(category.title) item")
                    .font(.headline)
                Spacer()
            }
            Form {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let item = TodoItem(category: category, title: title.isEmpty ? "Untitled" : title, notes: notes)
                    onAdd(item)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
