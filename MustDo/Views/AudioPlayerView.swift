import SwiftUI
import AVKit

struct AudioPlayerView: View {
    let url: URL
    @State private var player: AVPlayer = AVPlayer()
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text(url.lastPathComponent)
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button {
                    player.seek(to: .init(seconds: max(0, player.currentTime().seconds - 15), preferredTimescale: 600))
                } label: { Image(systemName: "gobackward.15") }
                .font(.title)
                Button {
                    if isPlaying { player.pause() } else { player.play() }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                Button {
                    player.seek(to: .init(seconds: player.currentTime().seconds + 30, preferredTimescale: 600))
                } label: { Image(systemName: "goforward.30") }
                .font(.title)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            isPlaying = false
        }
        .onDisappear { player.pause() }
    }
}
