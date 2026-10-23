import SwiftData
import SwiftUI

/// Leser for EPUB og artikler.
struct TextReaderView: View {
    @Bindable var book: Book
    let document: WebDocument

    @AppStorage("reader.theme") private var themeRaw = ReaderTheme.light.rawValue
    @AppStorage("reader.fontScale") private var fontScale = 1.0
    @AppStorage("reader.lineHeight") private var lineHeight = 1.5
    @AppStorage("reader.serif") private var serif = true
    @AppStorage("reader.tapToLookUp") private var tapToLookUp = true

    @Environment(\.modelContext) private var context
    @StateObject private var speech = SpeechReader.shared

    @State private var chapterIndex = 0
    @State private var progression = 0.0
    @State private var scrollRequest = 0
    @State private var scrollTarget = 0.0
    @State private var didRestore = false

    @State private var lookup: WordLookup?
    @State private var showTOC = false
    @State private var showBookmarks = false
    @State private var showAppearance = false
    @State private var showTranslation = false
    @State private var isSpeechActive = false

    private var theme: ReaderTheme { ReaderTheme(rawValue: themeRaw) ?? .light }
    private var appearance: ReaderAppearance {
        ReaderAppearance(theme: theme, fontScale: fontScale, lineHeight: lineHeight, serif: serif)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.backgroundColor.ignoresSafeArea()
            if let chapter = document.chapters[safe: chapterIndex] {
                WebContentView(
                    url: chapter.url,
                    readAccess: document.readAccess,
                    appearance: appearance,
                    tapToLookUp: tapToLookUp,
                    scrollRequest: scrollRequest,
                    scrollTarget: scrollTarget,
                    onProgress: { value in
                        progression = value
                        savePosition()
                    },
                    onWordTap: { lookup = $0 },
                    onNavigate: { url in
                        if let index = document.chapterIndex(for: url) { chapterIndex = index }
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 0) {
                if isSpeechActive {
                    SpeechPanel(speech: speech) { stopSpeech() }
                } else {
                    chapterBar
                }
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .navigationTitle(document.chapters[safe: chapterIndex]?.title ?? book.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .sheet(item: $lookup) { WordLookupView(lookup: $0) }
        .sheet(isPresented: $showTOC) { tocView }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(book: book) { jump(to: $0) }
        }
        .sheet(isPresented: $showTranslation) { translationView }
        .onAppear(perform: restore)
        .onDisappear {
            savePosition()
            if isSpeechActive { stopSpeech() }
        }
        .onChange(of: speech.section) {
            // Følg opplesingen til neste kapittel.
            if isSpeechActive, speech.section != chapterIndex {
                chapterIndex = speech.section
                scrollTarget = 0
            }
        }
    }

    // MARK: - Visninger

    private var chapterBar: some View {
        HStack {
            Button { go(toChapter: chapterIndex - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(chapterIndex == 0)
            Spacer()
            Text(progressText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(theme.foregroundColor.opacity(0.7))
            Spacer()
            Button { go(toChapter: chapterIndex + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(chapterIndex + 1 >= document.chapters.count)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.bottom, 4)
        .opacity(document.chapters.count > 1 ? 1 : 0)
    }

    private var progressText: String {
        let total = totalProgression
        if document.chapters.count > 1 {
            return "Kapittel \(chapterIndex + 1) av \(document.chapters.count) · \(Int((total * 100).rounded())) %"
        }
        return "\(Int((total * 100).rounded())) %"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !document.toc.isEmpty {
                Button { showTOC = true } label: { Label("Innhold", systemImage: "list.bullet") }
            }
            Button { addBookmark() } label: { Label("Legg til bokmerke", systemImage: "bookmark") }
            Button { showBookmarks = true } label: { Label("Bokmerker", systemImage: "bookmark.circle") }
            Button { isSpeechActive ? stopSpeech() : startSpeech() } label: {
                Label("Les høyt", systemImage: isSpeechActive ? "speaker.slash" : "speaker.wave.2")
            }
            if #available(iOS 18.0, macOS 15.0, *) {
                Button { showTranslation = true } label: { Label("Oversett", systemImage: "translate") }
            }
            Button { showAppearance = true } label: { Label("Utseende", systemImage: "textformat.size") }
                .popover(isPresented: $showAppearance) { AppearanceSettingsView() }
        }
    }

    private var tocView: some View {
        NavigationStack {
            List(document.toc) { entry in
                Button {
                    if let index = document.chapterIndex(for: entry.href) { go(toChapter: index) }
                    showTOC = false
                } label: {
                    Text(entry.title)
                        .padding(.leading, CGFloat(entry.level) * 16)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Innhold")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { showTOC = false } }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
    }

    @ViewBuilder
    private var translationView: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            FullTextTranslationView(
                title: document.chapters[safe: chapterIndex]?.title ?? book.title,
                paragraphs: document.textSource.paragraphs(inSection: chapterIndex)
            )
        }
    }

    // MARK: - Posisjon

    private var totalProgression: Double {
        guard !document.chapters.isEmpty else { return 0 }
        return (Double(chapterIndex) + progression) / Double(document.chapters.count)
    }

    private var currentPosition: ReadingPosition {
        ReadingPosition(
            href: document.chapters[safe: chapterIndex]?.href,
            progression: progression,
            totalProgression: totalProgression
        )
    }

    private func restore() {
        book.lastOpenedAt = .now
        guard !didRestore else { return }
        didRestore = true
        if let position = book.position {
            chapterIndex = document.chapterIndex(for: position.href) ?? 0
            progression = position.progression ?? 0
            scrollTarget = progression
        }
    }

    private func savePosition() {
        guard didRestore else { return }
        book.position = currentPosition
    }

    private func go(toChapter index: Int) {
        guard document.chapters.indices.contains(index) else { return }
        chapterIndex = index
        progression = 0
        scrollTarget = 0
        savePosition()
    }

    private func jump(to position: ReadingPosition) {
        let index = document.chapterIndex(for: position.href) ?? chapterIndex
        let target = position.progression ?? 0
        if index != chapterIndex {
            chapterIndex = index
            scrollTarget = target
        } else {
            scrollTarget = target
            scrollRequest += 1
        }
        progression = target
        savePosition()
    }

    private func addBookmark() {
        let chapterTitle = document.chapters[safe: chapterIndex]?.title
        let percent = "\(Int((totalProgression * 100).rounded())) %"
        let label = [chapterTitle, percent].compactMap { $0 }.joined(separator: " · ")
        book.addBookmark(at: currentPosition, label: label, context: context)
    }

    // MARK: - Opplesing

    private func startSpeech() {
        let length = document.characterCount(inChapter: chapterIndex)
        speech.onPositionChange = { [document] position in
            let section = position.page ?? 0
            let count = max(document.characterCount(inChapter: section), 1)
            let progress = Double(position.characterOffset ?? 0) / Double(count)
            book.position = ReadingPosition(
                href: document.chapters[safe: section]?.href,
                progression: progress,
                totalProgression: (Double(section) + progress) / Double(max(document.chapters.count, 1)),
                characterOffset: position.characterOffset
            )
        }
        speech.start(
            source: document.textSource,
            title: book.title,
            section: chapterIndex,
            characterOffset: Int(progression * Double(length))
        )
        isSpeechActive = true
    }

    private func stopSpeech() {
        speech.stop()
        speech.onPositionChange = nil
        isSpeechActive = false
        // Hopp til der opplesingen sluttet.
        if let position = book.position {
            jump(to: position)
        }
    }
}
