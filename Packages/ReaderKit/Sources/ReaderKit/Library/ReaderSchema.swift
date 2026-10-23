import Foundation
import SwiftData

public enum ReaderSchema {
    public static let models: [any PersistentModel.Type] = [
        Book.self,
        Bookmark.self,
        Highlight.self,
        CatalogSource.self,
    ]

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
