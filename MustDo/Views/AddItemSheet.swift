import SwiftUI
import UniformTypeIdentifiers

struct AddItemSheet: View {
    enum Payload {
        case text(title: String, notes: String)
        case url(title: String, urlString: String)
        case file(title: String, fileURL: URL)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case url = "URL"
        case file = "File"
        var id: String { rawValue }
    }

    let category: MustCategory
    let onAdd: (Payload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var urlInput: String = ""
    @State private var pickedFile: URL?
    @State private var mode: Mode = .url

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: category.systemImage)
                    .foregroundStyle(.tint)
                Text("New \(category.title) item")
                    .font(.headline)
                Spacer()
            }

            if category == .mustDo {
                textForm
            } else {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .url: urlForm
                case .file: fileForm
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var textForm: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    private var urlForm: some View {
        Form {
            TextField(urlPlaceholder, text: $urlInput)
            TextField("Title (optional)", text: $title)
                .help("Auto-filled from page metadata after adding")
        }
    }

    private var fileForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    chooseFile()
                } label: {
                    Label("Choose File…", systemImage: "folder")
                }
                if let url = pickedFile {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Title (optional)", text: $title)
        }
    }

    private var urlPlaceholder: String {
        switch category {
        case .mustWatch: return "YouTube / Twitter / video URL"
        case .mustRead: return "Web URL"
        case .mustListen: return "Podcast RSS or audio URL"
        default: return "URL"
        }
    }

    private var canSubmit: Bool {
        switch (category, mode) {
        case (.mustDo, _):
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case (_, .url):
            let s = urlInput.trimmingCharacters(in: .whitespaces)
            return !s.isEmpty && URL(string: s) != nil
        case (_, .file):
            return pickedFile != nil
        }
    }

    private func submit() {
        switch (category, mode) {
        case (.mustDo, _):
            onAdd(.text(title: title, notes: notes))
        case (_, .url):
            onAdd(.url(title: title, urlString: urlInput.trimmingCharacters(in: .whitespaces)))
        case (_, .file):
            if let url = pickedFile {
                onAdd(.file(title: title, fileURL: url))
            }
        }
        dismiss()
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = pickerTypes
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            pickedFile = panel.urls.first
        }
    }

    private var pickerTypes: [UTType] {
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
}
