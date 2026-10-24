import SwiftUI
import SwiftData
import ReaderKit

@main
struct ReaderApp: App {
    private let container: ModelContainer = {
        do {
            return try ReaderSchema.makeContainer()
        } catch {
            fatalError("Kunne ikke åpne biblioteket: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
