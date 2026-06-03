import SwiftUI
import SwiftData

@main
struct MustDoApp: App {
    @StateObject private var updater = UpdateService()

    let container: ModelContainer = {
        do {
            let schema = Schema([TodoItem.self, PodcastEpisode.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updater)
        }
        .modelContainer(container)
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
