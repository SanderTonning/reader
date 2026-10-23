import SwiftUI
import SwiftData

public struct RootView: View {
    public init() {}

    public var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Bibliotek", systemImage: "books.vertical") }
        }
    }
}
