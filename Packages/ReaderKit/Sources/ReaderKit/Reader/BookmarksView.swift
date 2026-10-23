import SwiftData
import SwiftUI

struct BookmarksView: View {
    @Bindable var book: Book
    var onSelect: (ReadingPosition) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if book.sortedBookmarks.isEmpty {
                    ContentUnavailableView("Ingen bokmerker", systemImage: "bookmark", description: Text("Trykk på bokmerke-knappen for å lagre et sted i boken."))
                } else {
                    List {
                        ForEach(book.sortedBookmarks) { bookmark in
                            Button {
                                if let position = bookmark.position {
                                    onSelect(position)
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.label).foregroundStyle(.primary)
                                    if let note = bookmark.note, !note.isEmpty {
                                        Text(note).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Text(bookmark.createdAt, format: .dateTime.day().month().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            let items = book.sortedBookmarks
                            for index in offsets { context.delete(items[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Bokmerker")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
    }
}

extension Book {
    /// Legger til et bokmerke på gitt posisjon.
    func addBookmark(at position: ReadingPosition, label: String, note: String? = nil, context: ModelContext) {
        let bookmark = Bookmark(label: label, note: note, position: position)
        context.insert(bookmark)
        bookmark.book = self
        try? context.save()
    }
}
