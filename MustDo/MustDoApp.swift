import SwiftUI
import SwiftData

@main
struct MustDoApp: App {
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
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
