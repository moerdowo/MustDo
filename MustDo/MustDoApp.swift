import SwiftUI
import SwiftData

/// Resolves where MustDo's SwiftData store lives and migrates data off the
/// old shared location.
///
/// Previously the app used a plain `ModelConfiguration(...)` with no URL,
/// which makes SwiftData store at `~/Library/Application Support/default.store`
/// — a NON-app-specific path shared by every non-sandboxed app that uses the
/// default configuration. That is fragile and non-standard. We now use an
/// explicit, app-owned path and copy any existing legacy store into it once.
enum StoreLocator {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("com.moerdowo.MustDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// New, app-specific store.
    static var storeURL: URL {
        appSupportDirectory.appendingPathComponent("MustDo.store")
    }

    /// Old shared SwiftData default location.
    static var legacyStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("default.store")
    }

    /// One-time copy of the legacy store (and its -wal/-shm sidecars) into the
    /// new location, only when the new store doesn't exist yet. Copies (does
    /// not move) so the legacy file remains as an extra safety backup.
    static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path),
              fm.fileExists(atPath: legacyStoreURL.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: legacyStoreURL.path + suffix)
            let dst = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
        NSLog("[MustDo] Migrated legacy store from \(legacyStoreURL.path) to \(storeURL.path)")
    }
}

@main
struct MustDoApp: App {
    @StateObject private var updater = UpdateService()
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer = MustDoApp.makeContainer()

    private static func makeContainer() -> ModelContainer {
        StoreLocator.migrateLegacyStoreIfNeeded()
        let schema = Schema([TodoItem.self, PodcastEpisode.self])
        let config = ModelConfiguration(schema: schema, url: StoreLocator.storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // NEVER silently wipe the user's data. If the store can't be opened
            // (e.g. an unmigratable schema change), move it aside as a dated
            // backup the user can recover, then start a fresh store so the app
            // still launches instead of crash-looping.
            NSLog("[MustDo] ModelContainer open failed: \(error). Backing up store and starting fresh.")
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: StoreLocator.storeURL.path + suffix)
                let dst = URL(fileURLWithPath: StoreLocator.storeURL.path + ".backup-\(stamp)" + suffix)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.moveItem(at: src, to: dst)
                }
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer even after backup: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updater)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Flush pending changes when the app is backgrounded or about to
            // quit, so data survives even if autosave hasn't fired yet.
            if phase != .active {
                try? container.mainContext.save()
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkManually()
                }
            }
        }
    }
}
