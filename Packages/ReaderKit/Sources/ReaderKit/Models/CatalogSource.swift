import Foundation
import SwiftData

public enum CatalogKind: String, Codable, CaseIterable, Sendable {
    case opds
    case librivox
    case gutendex
}

/// En katalog brukeren har lagt til selv, for eksempel en Calibre-server med OPDS.
@Model
public final class CatalogSource {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var url: URL
    public var kindRaw: String
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, url: URL, kind: CatalogKind = .opds, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.url = url
        self.kindRaw = kind.rawValue
        self.addedAt = addedAt
    }

    public var kind: CatalogKind {
        CatalogKind(rawValue: kindRaw) ?? .opds
    }
}
