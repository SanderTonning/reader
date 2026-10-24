import Foundation

/// Mappene der appen lagrer filer. Bøkene ligger i Dokumenter, så de vises i Filer-appen på iOS.
public enum LibraryFolder {
    public static var root: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Reader", isDirectory: true)
    }

    public static var books: URL { ensure(root.appendingPathComponent("Bøker", isDirectory: true)) }
    public static var covers: URL { ensure(root.appendingPathComponent("Omslag", isDirectory: true)) }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Et filnavn som ikke kolliderer med eksisterende filer i bibliotekmappen.
    public static func uniqueFileName(for original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var counter = 2
        while FileManager.default.fileExists(atPath: books.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }
}
