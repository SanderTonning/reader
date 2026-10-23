import Foundation
import SwiftData

@Model
public final class Bookmark {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var label: String
    public var note: String?
    public var positionData: Data?
    public var book: Book?

    public init(id: UUID = UUID(), label: String, note: String? = nil, position: ReadingPosition, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.note = note
        self.positionData = position.encoded()
        self.createdAt = createdAt
    }

    public var position: ReadingPosition? {
        get { ReadingPosition.decode(positionData) }
        set { positionData = newValue?.encoded() }
    }
}

@Model
public final class Highlight {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var text: String
    public var colorName: String
    public var note: String?
    public var positionData: Data?
    public var book: Book?

    public init(id: UUID = UUID(), text: String, colorName: String = "yellow", note: String? = nil, position: ReadingPosition, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.colorName = colorName
        self.note = note
        self.positionData = position.encoded()
        self.createdAt = createdAt
    }

    public var position: ReadingPosition? {
        get { ReadingPosition.decode(positionData) }
        set { positionData = newValue?.encoded() }
    }
}
