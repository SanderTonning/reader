import Foundation

public enum BookKind: String, Codable, CaseIterable, Sendable {
    case ebook
    case audiobook
    case article
}

public enum BookFormat: String, Codable, CaseIterable, Sendable {
    case epub
    case pdf
    case audio
    case article

    public init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "mp3", "m4a", "m4b", "aac", "wav": self = .audio
        case "html", "htm", "txt", "md": self = .article
        default: return nil
        }
    }

    public var kind: BookKind {
        switch self {
        case .epub, .pdf: .ebook
        case .audio: .audiobook
        case .article: .article
        }
    }
}
