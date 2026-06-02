import SwiftUI
import AVKit

/// VideoPlayer wrapper that keeps a single AVPlayer alive across body
/// re-evaluations. The previous code built `AVPlayer(url:)` inline,
/// which made SwiftUI recreate the underlying NSViewRepresentable on
/// every diff and was implicated in a Swift-runtime metadata crash on
/// macOS 26 when the detail pane transitioned in after a drag-and-drop.
struct StableVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer = AVPlayer()
    @State private var loadedURL: URL?

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                if loadedURL != url {
                    player.replaceCurrentItem(with: AVPlayerItem(url: url))
                    loadedURL = url
                }
            }
            .onDisappear { player.pause() }
    }
}
