import SwiftUI
import AVKit

/// Plain NSViewRepresentable around AVPlayerView.
///
/// Why not SwiftUI's VideoPlayer? On macOS 26 the metadata resolution
/// for `VideoPlayer<EmptyView>` aborts in `getSuperclassMetadata` the
/// first time SwiftUI tries to materialize it inside our detail pane.
/// PDFReaderView / WebPageView (both bare NSViewRepresentables) work,
/// so we mirror that pattern here.
struct StableVideoPlayer: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var loadedURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.player = AVPlayer()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if context.coordinator.loadedURL != url {
            view.player?.replaceCurrentItem(with: AVPlayerItem(url: url))
            context.coordinator.loadedURL = url
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
    }
}
