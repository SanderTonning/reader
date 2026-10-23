import AVFoundation
import Foundation
import MediaPlayer

/// Spiller lydbøker (lokale filer eller strømming) med kontroller på låseskjermen.
@MainActor
public final class AudioPlayer: ObservableObject {
    public static let shared = AudioPlayer()

    @Published public private(set) var book: Book?
    @Published public private(set) var tracks: [AudioTrack] = []
    @Published public private(set) var trackIndex = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: Double = 0
    @Published public private(set) var duration: Double = 0
    @Published public var rate: Float = 1.0 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "audio.rate")
            if isPlaying { player.rate = rate }
        }
    }
    /// Når sovetimeren stopper avspillingen.
    @Published public private(set) var sleepTimerEnd: Date?
    /// Minispilleren skjules mens den store spillervisningen er åpen.
    @Published var isFullPlayerVisible = false

    public var isActive: Bool { book != nil && isPlaying }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSavedTime: Double = -100
    private var sleepTimer: Timer?
    private var remoteCommandsConfigured = false

    init() {
        if let saved = UserDefaults.standard.object(forKey: "audio.rate") as? Float { rate = saved }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time.seconds)
            }
        }
    }

    public func load(_ book: Book, autoplay: Bool = true) {
        if self.book?.id == book.id {
            if autoplay && !isPlaying { play() }
            return
        }
        savePosition()
        self.book = book
        tracks = book.tracks
        let position = book.position
        selectTrack(position?.track ?? 0, at: position?.seconds ?? 0)
        configureAudioSession()
        setUpRemoteCommands()
        if autoplay { play() }
    }

    public func url(for track: AudioTrack) -> URL? {
        if let fileName = track.fileName {
            let local = LibraryFolder.books.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: local.path) { return local }
        }
        return track.remoteURL
    }

    public func play() {
        guard book != nil else { return }
        if SpeechReader.shared.isSpeaking { SpeechReader.shared.stop() }
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    public func pause() {
        player.pause()
        isPlaying = false
        savePosition()
        updateNowPlaying()
    }

    public func togglePlay() { isPlaying ? pause() : play() }

    /// Stopper og glemmer gjeldende bok, for eksempel når den slettes.
    public func unload() {
        pause()
        player.replaceCurrentItem(with: nil)
        book = nil
        tracks = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    public func skip(by seconds: Double) {
        seek(to: max(currentTime + seconds, 0))
    }

    public func seek(to seconds: Double) {
        let target = duration > 0 ? min(seconds, duration - 0.5) : seconds
        player.seek(to: CMTime(seconds: max(target, 0), preferredTimescale: 600))
        currentTime = max(target, 0)
        savePosition()
        updateNowPlaying()
    }

    public func selectTrack(_ index: Int, at seconds: Double = 0) {
        guard tracks.indices.contains(index), let url = url(for: tracks[index]) else { return }
        trackIndex = index
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.trackEnded()
            }
        }
        duration = tracks[index].duration ?? 0
        currentTime = seconds
        if seconds > 0 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        if isPlaying { player.playImmediately(atRate: rate) }
        Task { [weak self] in
            if let loaded = try? await item.asset.load(.duration), loaded.isNumeric {
                self?.duration = loaded.seconds
                self?.updateNowPlaying()
            }
        }
        updateNowPlaying()
    }

    public func nextTrack() { selectTrack(trackIndex + 1) }
    public func previousTrack() {
        if currentTime > 5 { seek(to: 0) } else { selectTrack(max(trackIndex - 1, 0)) }
    }

    /// Sovetimer i minutter. Nil slår den av.
    public func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        guard let minutes else {
            sleepTimerEnd = nil
            return
        }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEnd = end
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pause()
                self?.sleepTimerEnd = nil
            }
        }
    }

    public var currentPosition: ReadingPosition {
        let totalDuration = tracks.compactMap(\.duration).reduce(0, +)
        let elapsed = tracks.prefix(trackIndex).compactMap(\.duration).reduce(0, +) + currentTime
        return ReadingPosition(
            totalProgression: totalDuration > 0 ? min(elapsed / totalDuration, 1) : Double(trackIndex) / Double(max(tracks.count, 1)),
            track: trackIndex,
            seconds: currentTime
        )
    }

    public func savePosition() {
        guard let book else { return }
        book.position = currentPosition
        lastSavedTime = currentTime
    }

    // MARK: - Intern logikk

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        if abs(seconds - lastSavedTime) >= 10 { savePosition() }
        updateNowPlaying()
    }

    private func trackEnded() {
        if trackIndex + 1 < tracks.count {
            selectTrack(trackIndex + 1)
        } else {
            pause()
            book?.finishedAt = .now
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        #endif
    }

    private func setUpRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.book != nil else { return .noActionableNowPlayingItem }
            self.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.book != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(by: 30)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(by: -15)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let book else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: tracks.count > 1 ? (tracks[safe: trackIndex]?.title ?? book.title) : book.title,
            MPMediaItemPropertyAlbumTitle: book.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
        if let author = book.author { info[MPMediaItemPropertyArtist] = author }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
