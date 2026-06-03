import SwiftUI
import AVKit

struct AudioPlayerView: View {
    let url: URL

    @State private var player: AVPlayer = AVPlayer()
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

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

            // Scrubber + time tracker
            VStack(spacing: 4) {
                Slider(
                    value: $currentTime,
                    in: 0...max(duration, 0.1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                        }
                    }
                )
                .tint(.accentColor)
                .disabled(duration <= 0)

                HStack {
                    Text(timeString(currentTime))
                    Spacer()
                    Text(duration > 0 ? "-" + timeString(max(0, duration - currentTime)) : "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 380)

            HStack(spacing: 24) {
                Button {
                    seek(by: -15)
                } label: { Image(systemName: "gobackward.15") }
                .font(.title)

                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button {
                    seek(by: 30)
                } label: { Image(systemName: "goforward.30") }
                .font(.title)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            currentTime = 0
            duration = 0
            isPlaying = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            await loadDuration()
        }
        .onAppear { addTimeObserver() }
        .onDisappear {
            removeTimeObserver()
            player.pause()
        }
    }

    private func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func seek(by delta: Double) {
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude,
                                player.currentTime().seconds + delta))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
    }

    private func addTimeObserver() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            if !isScrubbing, time.seconds.isFinite {
                currentTime = time.seconds
            }
            if let item = player.currentItem {
                let d = item.duration.seconds
                if d.isFinite, d > 0 { duration = d }
            }
            isPlaying = player.timeControlStatus == .playing
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserver {
            player.removeTimeObserver(token)
            timeObserver = nil
        }
    }

    private func loadDuration() async {
        guard let item = player.currentItem else { return }
        if let d = try? await item.asset.load(.duration) {
            let secs = d.seconds
            if secs.isFinite, secs > 0 {
                await MainActor.run { duration = secs }
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
