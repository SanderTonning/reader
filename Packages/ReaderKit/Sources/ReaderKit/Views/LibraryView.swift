import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView(
                    "Biblioteket er tomt",
                    systemImage: "books.vertical",
                    description: Text("Importer egne filer eller finn bøker i åpne bibliotek.")
                )
            } else {
                List(books) { book in
                    BookRow(book: book)
                }
            }
        }
        .navigationTitle("Bibliotek")
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.title).font(.headline)
            if let author = book.author {
                Text(author).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
