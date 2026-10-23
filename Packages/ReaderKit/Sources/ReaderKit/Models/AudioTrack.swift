import Foundation

/// Ett spor i en lydbok, enten en lokal fil eller en strømme-URL.
public struct AudioTrack: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var title: String
    public var fileName: String?
    public var remoteURL: URL?
    public var duration: Double?

    public init(index: Int, title: String, fileName: String? = nil, remoteURL: URL? = nil, duration: Double? = nil) {
        self.index = index
        self.title = title
        self.fileName = fileName
        self.remoteURL = remoteURL
        self.duration = duration
    }
}
