import PDFKit
import SwiftData
import SwiftUI

struct PDFReaderView: View {
    @Bindable var book: Book
    let document: PDFDocument

    @Environment(\.modelContext) private var context
    @StateObject private var speech = SpeechReader.shared
    @State private var pageIndex = 0
    @State private var jumpRequest = 0
    @State private var didRestore = false
    @State private var showBookmarks = false
    @State private var showTranslation = false
    @State private var isSpeechActive = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PDFKitView(document: document, pageIndex: $pageIndex, jumpRequest: jumpRequest)
                .ignoresSafeArea(edges: .bottom)
            if isSpeechActive {
                SpeechPanel(speech: speech) { stopSpeech() }
            } else {
                Text("Side \(pageIndex + 1) av \(document.pageCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 6)
            }
        }
        .navigationTitle(book.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { addBookmark() } label: { Label("Legg til bokmerke", systemImage: "bookmark") }
                Button { showBookmarks = true } label: { Label("Bokmerker", systemImage: "bookmark.circle") }
                Button { isSpeechActive ? stopSpeech() : startSpeech() } label: {
                    Label("Les høyt", systemImage: isSpeechActive ? "speaker.slash" : "speaker.wave.2")
                }
                if #available(iOS 18.0, macOS 15.0, *) {
                    Button { showTranslation = true } label: { Label("Oversett side", systemImage: "translate") }
                }
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView(book: book) { position in
                pageIndex = position.page ?? 0
                jumpRequest += 1
            }
        }
        .sheet(isPresented: $showTranslation) {
            if #available(iOS 18.0, macOS 15.0, *) {
                FullTextTranslationView(title: "Side \(pageIndex + 1)", paragraphs: PDFTextSource(document: document).paragraphs(inSection: pageIndex))
            }
        }
        .onAppear {
            book.lastOpenedAt = .now
            guard !didRestore else { return }
            didRestore = true
            pageIndex = min(book.position?.page ?? 0, max(document.pageCount - 1, 0))
            jumpRequest += 1
        }
        .onChange(of: pageIndex) {
            guard didRestore else { return }
            book.position = position
        }
        .onChange(of: speech.section) {
            if isSpeechActive, speech.section != pageIndex {
                pageIndex = speech.section
                jumpRequest += 1
            }
        }
        .onDisappear {
            if isSpeechActive { stopSpeech() }
        }
    }

    private var position: ReadingPosition {
        ReadingPosition(
            totalProgression: document.pageCount > 0 ? Double(pageIndex + 1) / Double(document.pageCount) : 0,
            page: pageIndex
        )
    }

    private func addBookmark() {
        book.addBookmark(at: position, label: "Side \(pageIndex + 1)", context: context)
    }

    private func startSpeech() {
        speech.onPositionChange = nil
        speech.start(source: PDFTextSource(document: document), title: book.title, section: pageIndex)
        isSpeechActive = true
    }

    private func stopSpeech() {
        speech.stop()
        isSpeechActive = false
    }
}

struct PDFKitView {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let jumpRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    fileprivate func makeView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        context.coordinator.view = view
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    fileprivate func update(context: Context) {
        context.coordinator.parent = self
        if context.coordinator.handledJump != jumpRequest {
            context.coordinator.handledJump = jumpRequest
            if let page = document.page(at: pageIndex) {
                DispatchQueue.main.async { context.coordinator.view?.go(to: page) }
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var view: PDFView?
        var handledJump = -1

        init(parent: PDFKitView) { self.parent = parent }

        @objc func pageChanged(_ notification: Notification) {
            guard let view, let page = view.currentPage, let document = view.document else { return }
            let index = document.index(for: page)
            if index != parent.pageIndex { parent.pageIndex = index }
        }
    }
}

#if os(iOS)
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView(context: context) }
    func updateUIView(_ view: PDFView, context: Context) { update(context: context) }
}
#else
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView(context: context) }
    func updateNSView(_ view: PDFView, context: Context) { update(context: context) }
}
#endif
