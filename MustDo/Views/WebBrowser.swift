import SwiftUI
import AppKit
@preconcurrency import WebKit

/// Observable wrapper around a single WKWebView, exposing navigation
/// state for a SwiftUI toolbar. The web view is created once and reused
/// across body re-evaluations.
final class WebBrowserModel: ObservableObject {
    let webView: WKWebView

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""

    private var observers: [NSKeyValueObservation] = []
    private var loadedURL: URL?

    init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)

        func bind<V>(_ keyPath: KeyPath<WKWebView, V>, _ apply: @escaping (WebBrowserModel, V) -> Void) {
            let token = webView.observe(keyPath, options: [.initial, .new]) { [weak self] webView, _ in
                let value = webView[keyPath: keyPath]
                DispatchQueue.main.async {
                    guard let self else { return }
                    apply(self, value)
                }
            }
            observers.append(token)
        }

        bind(\.canGoBack) { $0.canGoBack = $1 }
        bind(\.canGoForward) { $0.canGoForward = $1 }
        bind(\.isLoading) { $0.isLoading = $1 }
        bind(\.estimatedProgress) { $0.progress = $1 }
        bind(\.url) { $0.currentURL = $1 }
        bind(\.title) { $0.pageTitle = $1 ?? "" }
    }

    func loadIfNeeded(_ url: URL) {
        guard loadedURL != url else { return }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
}

private struct WebViewContainer: NSViewRepresentable {
    let model: WebBrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// In-app browser: toolbar (back / forward / reload-stop / address /
/// open-in-default-browser) + a load-progress bar + the web content.
struct WebBrowser: View {
    let url: URL
    @StateObject private var model = WebBrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack(alignment: .top) {
                WebViewContainer(model: model)
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
        }
        .onAppear { model.loadIfNeeded(url) }
        .onChange(of: url) { _, newURL in model.loadIfNeeded(newURL) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Back")

            Button { model.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Forward")

            Button {
                if model.isLoading { model.stop() } else { model.reload() }
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(model.isLoading ? "Stop" : "Reload")

            Text(model.currentURL?.absoluteString ?? url.absoluteString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSWorkspace.shared.open(model.currentURL ?? url)
            } label: {
                Image(systemName: "safari")
            }
            .help("Open in default browser")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
