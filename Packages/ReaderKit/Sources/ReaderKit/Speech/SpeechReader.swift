import AVFoundation
import Foundation
import MediaPlayer
import NaturalLanguage

/// Leser tekst høyt med Apples innebygde stemmer (gratis, på enheten), også i bakgrunnen.
@MainActor
public final class SpeechReader: NSObject, ObservableObject {
    public static let shared = SpeechReader()

    @Published public private(set) var isSpeaking = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var section = 0
    @Published public private(set) var paragraphIndex = 0
    @Published public private(set) var paragraphs: [String] = []
    /// Området i gjeldende avsnitt som leses nå (for markering).
    @Published public private(set) var spokenRange: NSRange?
    @Published public var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet { UserDefaults.standard.set(rate, forKey: "speech.rate") }
    }
    @Published public var voiceIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "speech.voice") }
    }

    public private(set) var source: TextSource?
    public private(set) var title: String = ""
    /// Kalles når posisjonen endrer seg, så den kan lagres på boken.
    public var onPositionChange: ((ReadingPosition) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var detectedLanguage: String?
    private var paragraphStartOffset = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        if let saved = UserDefaults.standard.object(forKey: "speech.rate") as? Float { rate = saved }
        voiceIdentifier = UserDefaults.standard.string(forKey: "speech.voice")
    }

    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: " · Premium"
        case .enhanced: " · Forbedret"
        default: ""
        }
    }

    /// Stemmer for et språk, beste kvalitet først.
    public static func voices(for language: String?) -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let prefix = language.map { String($0.prefix(2)) }
        // Morostemmene (Bells, Bad News …) har samme kvalitet som vanlige stemmer og havnet ofte først.
        let usable = all.filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
        let matching = prefix.map { p in usable.filter { $0.language.hasPrefix(p) } } ?? usable
        let systemDefault = language.flatMap { AVSpeechSynthesisVoice(language: $0)?.identifier }
        return matching.sorted { a, b in
            if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
            if (a.identifier == systemDefault) != (b.identifier == systemDefault) { return a.identifier == systemDefault }
            return a.name < b.name
        }
    }

    public var language: String? { detectedLanguage }

    public func start(source: TextSource, title: String, section: Int = 0, characterOffset: Int = 0) {
        stop()
        self.source = source
        self.title = title
        configureAudioSession()
        setUpRemoteCommands()
        load(section: section)
        detectedLanguage = Self.detectLanguage(source: source, sample: paragraphs)
        // Finn avsnittet som inneholder tegnposisjonen.
        var offset = 0
        var startIndex = 0
        for (index, paragraph) in paragraphs.enumerated() {
            if offset + paragraph.count > characterOffset { startIndex = index; break }
            offset += paragraph.count + 1
            startIndex = index
        }
        speak(paragraph: startIndex)
    }

    public func togglePause() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        } else if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            reportPosition()
        } else if source != nil {
            speak(paragraph: paragraphIndex)
        }
        updateNowPlaying()
    }

    public func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            reportPosition()
        }
        pendingStop = true
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        spokenRange = nil
    }

    public func nextParagraph() { speak(paragraph: paragraphIndex + 1) }
    public func previousParagraph() { speak(paragraph: max(paragraphIndex - 1, 0)) }

    public func restartCurrentWithNewSettings() {
        guard isSpeaking else { return }
        speak(paragraph: paragraphIndex)
    }

    // MARK: - Intern logikk

    private var pendingStop = false

    private func load(section: Int) {
        guard let source else { return }
        self.section = section
        paragraphs = source.paragraphs(inSection: section)
        paragraphIndex = 0
    }

    private func speak(paragraph index: Int) {
        guard let source else { return }
        var index = index
        // Hopp til neste seksjon når avsnittene er brukt opp (tomme sider hoppes over).
        while index >= paragraphs.count {
            guard section + 1 < source.sectionCount else {
                finish()
                return
            }
            load(section: section + 1)
            index = 0
        }
        pendingStop = true
        synthesizer.stopSpeaking(at: .immediate)
        pendingStop = false

        paragraphIndex = index
        paragraphStartOffset = paragraphs.prefix(index).reduce(0) { $0 + $1.count + 1 }
        spokenRange = nil

        let utterance = AVSpeechUtterance(string: paragraphs[index])
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.15
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else if let language = detectedLanguage {
            utterance.voice = Self.voices(for: language).first ?? AVSpeechSynthesisVoice(language: language)
        }
        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
        reportPosition()
        updateNowPlaying()
    }

    private func finish() {
        isSpeaking = false
        isPaused = false
        spokenRange = nil
        reportPosition()
        updateNowPlaying()
    }

    private func reportPosition() {
        guard let source else { return }
        let total = Double(section) / Double(max(source.sectionCount, 1))
        onPositionChange?(ReadingPosition(
            totalProgression: total,
            page: section,
            characterOffset: paragraphStartOffset + (spokenRange?.location ?? 0)
        ))
    }

    private static func detectLanguage(source: TextSource, sample: [String]) -> String? {
        if let language = source.language, !language.isEmpty { return language }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample.prefix(8).joined(separator: " "))
        return recognizer.dominantLanguage?.rawValue
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        #endif
    }

    private var remoteCommandsConfigured = false

    private func setUpRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.source != nil, !AudioPlayer.shared.isActive else { return .noActionableNowPlayingItem }
            self.togglePause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.source != nil, !AudioPlayer.shared.isActive else { return .noActionableNowPlayingItem }
            self.nextParagraph()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.source != nil, !AudioPlayer.shared.isActive else { return .noActionableNowPlayingItem }
            self.previousParagraph()
            return .success
        }
    }

    private func updateNowPlaying() {
        guard !AudioPlayer.shared.isActive else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: title]
        if let sectionTitle = source?.title(ofSection: section) {
            info[MPMediaItemPropertyArtist] = sectionTitle
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = (isSpeaking && !isPaused) ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension SpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.spokenRange = characterRange
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.pendingStop, self.isSpeaking else { return }
            self.speak(paragraph: self.paragraphIndex + 1)
        }
    }
}
