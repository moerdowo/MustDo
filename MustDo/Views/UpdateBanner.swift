import SwiftUI

/// Top-of-window banner reflecting UpdateService state. Hidden when idle
/// or up-to-date; shows download progress, then a one-click install.
struct UpdateBanner: View {
    @ObservedObject var updater: UpdateService
    @State private var showNotes = false

    var body: some View {
        switch updater.state {
        case .downloading(let progress, let release):
            banner(tint: .accentColor) {
                Image(systemName: "arrow.down.circle")
                HStack(spacing: 8) {
                    Text("Downloading MustDo \(release.version)…")
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 140)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

        case .readyToInstall(_, let release):
            banner(tint: .accentColor) {
                Image(systemName: "arrow.up.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("MustDo \(release.version) is ready to install")
                        .fontWeight(.medium)
                    if !release.notes.isEmpty {
                        Button(showNotes ? "Hide release notes" : "What's new?") {
                            showNotes.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                Spacer()
                Button("Later") { updater.dismiss() }
                Button("Install & Relaunch") { updater.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
            } extra: {
                if showNotes, case .readyToInstall(_, let r) = updater.state, !r.notes.isEmpty {
                    ScrollView {
                        Text(r.notes)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    .padding(.top, 4)
                }
            }

        case .failed(let message):
            banner(tint: .orange) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Update failed: \(message)")
                    .lineLimit(2)
                Spacer()
                Button("Retry") { updater.checkManually() }
                Button("Dismiss") { updater.dismiss() }
            }

        case .idle, .checking, .upToDate:
            EmptyView()
        }
    }

    @ViewBuilder
    private func banner<Content: View, Extra: View>(
        tint: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    content()
                }
                extra()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12))
            .overlay(alignment: .leading) {
                Rectangle().fill(tint).frame(width: 3)
            }
            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
