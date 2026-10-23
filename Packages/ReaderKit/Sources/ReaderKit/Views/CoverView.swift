import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Omslagsbilde, eller et generert omslag med tittel når boken mangler bilde.
struct CoverView: View {
    let book: Book

    var body: some View {
        Group {
            if let fileName = book.coverFileName,
               let image = PlatformImage(contentsOfFile: LibraryFolder.covers.appendingPathComponent(fileName).path) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let url = book.coverURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.85), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(book.title)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                if let author = book.author {
                    Text(author).font(.caption2).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(8)
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    private var icon: String {
        switch book.kind {
        case .ebook: "book.closed"
        case .audiobook: "headphones"
        case .article: "doc.text"
        }
    }

    private var color: Color {
        let palette: [Color] = [.indigo, .teal, .brown, .purple, .blue, .orange, .green, .pink]
        let hash = book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

#if os(iOS)
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#else
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif
