import SwiftUI
@preconcurrency import WebKit

struct EPUBReaderView: View {
    let epubURL: URL
    @State private var unpacked: EPUBLoader.UnpackedEPUB?
    @State private var currentIndex: Int = 0
    @State private var error: String?

    var body: some View {
        Group {
            if let unp = unpacked {
                VStack(spacing: 0) {
                    EPUBWebView(file: unp.spine[currentIndex])
                    Divider()
                    HStack {
                        Button {
                            currentIndex = max(0, currentIndex - 1)
                        } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(currentIndex == 0)

                        Spacer()
                        Text("Chapter \(currentIndex + 1) of \(unp.spine.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()

                        Button {
                            currentIndex = min(unp.spine.count - 1, currentIndex + 1)
                        } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(currentIndex >= unp.spine.count - 1)
                    }
                    .padding(8)
                }
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Couldn't open EPUB")
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Loading EPUB…")
            }
        }
        .task(id: epubURL) {
            error = nil
            unpacked = nil
            currentIndex = 0
            do {
                let u = try EPUBLoader.unpack(epubURL: epubURL)
                unpacked = u
            } catch {
                self.error = (error as NSError).localizedDescription
            }
        }
    }
}

struct EPUBWebView: NSViewRepresentable {
    let file: URL
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        loadFile(into: view)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        loadFile(into: view)
    }
    private func loadFile(into view: WKWebView) {
        // Allow access to sibling resources inside the EPUB
        let directory = file.deletingLastPathComponent()
        view.loadFileURL(file, allowingReadAccessTo: directory.deletingLastPathComponent())
    }
}
