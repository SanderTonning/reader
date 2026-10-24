import Foundation

/// Hvor langt man har kommet i en bok, uavhengig av om den leses, lyttes til eller leses opp.
/// Lagres som JSON på boken og i bokmerker, og er det som synkes mellom enheter.
public struct ReadingPosition: Codable, Hashable, Sendable {
    /// Ressurs i boken, for eksempel et kapittel i en EPUB.
    public var href: String?
    /// Fremdrift innenfor ressursen, 0...1.
    public var progression: Double?
    /// Fremdrift i hele boken, 0...1.
    public var totalProgression: Double?
    /// Sidetall i PDF (0-basert).
    public var page: Int?
    /// Spor i en lydbok (0-basert).
    public var track: Int?
    /// Sekunder inn i sporet.
    public var seconds: Double?
    /// Tegnposisjon i ren tekst, brukt av opplesing og artikler.
    public var characterOffset: Int?
    /// Readium-locator som JSON, når den finnes.
    public var locatorJSON: String?

    public var updatedAt: Date
    public var deviceName: String

    public init(
        href: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil,
        page: Int? = nil,
        track: Int? = nil,
        seconds: Double? = nil,
        characterOffset: Int? = nil,
        locatorJSON: String? = nil,
        updatedAt: Date = .now,
        deviceName: String = DeviceInfo.name
    ) {
        self.href = href
        self.progression = progression
        self.totalProgression = totalProgression
        self.page = page
        self.track = track
        self.seconds = seconds
        self.characterOffset = characterOffset
        self.locatorJSON = locatorJSON
        self.updatedAt = updatedAt
        self.deviceName = deviceName
    }

    /// Kort tekst til visning, for eksempel «42 %».
    public var percentText: String? {
        guard let totalProgression else { return nil }
        return "\(Int((totalProgression * 100).rounded())) %"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public func encoded() -> Data? {
        try? Self.encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> ReadingPosition? {
        guard let data else { return nil }
        return try? decoder.decode(ReadingPosition.self, from: data)
    }
}
