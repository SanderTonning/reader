import SwiftData
import SwiftUI

struct AudioPlayerView: View {
    @Bindable var book: Book
    @StateObject private var player = AudioPlayer.shared
    @Environment(\.modelContext) private var context
    @State private var scrubbing: Double?
    @State private var showBookmarks = false
    @State private var downloadProgress: Double?
    @State private var downloadError: String?

    private var needsDownload: Bool {
        book.tracks.contains { track in
            track.remoteURL != nil && !(track.fileName.map { FileManager.default.fileExists(atPath: LibraryFolder.books.appendingPathComponent($0).path) } ?? false)
        }
    }

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CoverView(book: book)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .shadow(radius: 8)
                    .padding(.top)

                VStack(spacing: 4) {
                    Text(book.title).font(.title2.bold()).multilineTextAlignment(.center)
                    if let author = book.author { Text(author).foregroundStyle(.secondary) }
                    if player.tracks.count > 1, let track = player.tracks[safe: player.trackIndex] {
                        Text(track.title).font(.callout).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { scrubbing ?? player.currentTime }, set: { scrubbing = $0 }),
                        in: 0...max(player.duration, 1),
                        onEditingChanged: { editing in
                            if !editing, let value = scrubbing {
                                player.seek(to: value)
                                scrubbing = nil
                            }
                        }
                    )
                    HStack {
                        Text(Self.format(scrubbing ?? player.currentTime))
                        Spacer()
                        Text("-" + Self.format(max(player.duration - (scrubbing ?? player.currentTime), 0)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                HStack(spacing: 36) {
                    Button { player.previousTrack() } label: { Image(systemName: "backward.end.fill") }
                        .disabled(player.tracks.count < 2)
                    Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                    }
                    Button { player.skip(by: 30) } label: { Image(systemName: "goforward.30") }
                    Button { player.nextTrack() } label: { Image(systemName: "forward.end.fill") }
                        .disabled(player.trackIndex + 1 >= player.tracks.count)
                }
                .font(.title2)
                .buttonStyle(.borderless)

                HStack(spacing: 24) {
                    Menu {
                        ForEach(rates, id: \.self) { rate in
                            Button("\(rate.formatted())x") { player.rate = rate }
                        }
                    } label: {
                        Label("\(player.rate.formatted())x", systemImage: "speedometer")
                    }
                    Menu {
                        Button("Av") { player.setSleepTimer(minutes: nil) }
                        ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                            Button("\(minutes) min") { player.setSleepTimer(minutes: minutes) }
                        }
                    } label: {
                        if let end = player.sleepTimerEnd {
                            Label { Text(end, style: .timer) } icon: { Image(systemName: "moon.zzz.fill") }
                        } else {
                            Label("Sovetimer", systemImage: "moon.zzz")
                        }
                    }
                    Button { addBookmark() } label: { Label("Bokmerke", systemImage: "bookmark") }
                    Button { showBookmarks = true } label: { Label("Bokmerker", systemImage: "bookmark.circle") }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)

                if needsDownload {
                    if let downloadProgress {
                        ProgressView("Laster ned …", value: downloadProgress).padding(.horizontal)
                    } else {
                        Button { Task { await download() } } label: {
                            Label("Last ned for lytting uten nett", systemImage: "arrow.down.circle")
                        }
                    }
                }
                if let downloadError { Text(downloadError).font(.caption).foregroundStyle(.red) }

                if player.tracks.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(player.tracks) { track in
                            Button { player.selectTrack(track.index); player.play() } label: {
                                HStack {
                                    Text(track.title).lineLimit(1)
                                    Spacer()
                                    if let duration = track.duration { Text(Self.format(duration)).foregroundStyle(.secondary) }
                                }
                                .font(track.index == player.trackIndex ? .body.bold() : .body)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(book.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            book.lastOpenedAt = .now
            player.load(book, autoplay: false)
            player.isFullPlayerVisible = true
        }
        .onDisappear {
            player.isFullPlayerVisible = false
            player.savePosition()
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(book: book) { position in
                player.selectTrack(position.track ?? 0, at: position.seconds ?? 0)
            }
        }
    }

    private func download() async {
        downloadError = nil
        downloadProgress = 0
        do {
            try await CatalogImporter.downloadAudio(book) { value in
                Task { @MainActor in downloadProgress = value }
            }
        } catch {
            downloadError = "Nedlastingen feilet: \(error.localizedDescription)"
        }
        downloadProgress = nil
    }

    private func addBookmark() {
        player.savePosition()
        let position = player.currentPosition
        let trackTitle = player.tracks.count > 1 ? player.tracks[safe: player.trackIndex]?.title : nil
        let label = [trackTitle, Self.format(player.currentTime)].compactMap { $0 }.joined(separator: " · ")
        book.addBookmark(at: position, label: label, context: context)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
