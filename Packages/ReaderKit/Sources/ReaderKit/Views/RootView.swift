import SwiftData
import SwiftUI

public struct RootView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var importState = ImportState()
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var sync = SyncEngine.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LibraryView()
            }
            .safeAreaInset(edge: .bottom) { miniPlayer }
            .tabItem { Label("Bibliotek", systemImage: "books.vertical") }
            .tag(0)

            NavigationStack {
                ExploreView()
            }
            .safeAreaInset(edge: .bottom) { miniPlayer }
            .tabItem { Label("Utforsk", systemImage: "building.columns") }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Innstillinger", systemImage: "gearshape") }
            .tag(2)
        }
        .environmentObject(importState)
        .onOpenURL(perform: handle)
        .task {
            DeviceInfo.prepare()
            // Synk ved oppstart og deretter hvert andre minutt mens appen er åpen.
            while !Task.isCancelled {
                await sync.sync(context: context)
                try? await Task.sleep(for: .seconds(120))
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                AudioPlayer.shared.savePosition()
            }
            Task { await sync.sync(context: context) }
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if let book = player.book {
            HStack(spacing: 12) {
                CoverView(book: book).frame(width: 36, height: 36)
                VStack(alignment: .leading) {
                    Text(book.title).font(.subheadline.bold()).lineLimit(1)
                    Text(AudioPlayerView.format(player.currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                Button { player.togglePlay() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                Button { player.unload() } label: { Image(systemName: "xmark") }
            }
            .buttonStyle(.borderless)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    /// Filer som åpnes med appen, og reader://add?url=… fra en snarvei i delingsmenyen.
    private func handle(_ url: URL) {
        if url.isFileURL {
            importState.importFiles([url], context: context)
            return
        }
        guard url.scheme == "reader",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let value = components.queryItems?.first { $0.name == "url" || $0.name == "text" }?.value ?? ""
        if let articleURL = ArticleImporter.firstURL(in: value) {
            tab = 0
            importState.importArticle(articleURL, context: context)
        }
    }
}
