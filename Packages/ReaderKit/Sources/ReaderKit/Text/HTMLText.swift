import Foundation

/// Gjør HTML/XHTML om til ren tekst, delt i avsnitt. Brukes av opplesing og oversettelse.
public enum HTMLText {
    private static let blockTags = ["p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "tr", "section", "article", "pre", "dd", "dt", "figcaption"]

    public static func plainText(from html: String) -> String {
        var text = html
        // Fjern hode, skript og stil.
        for tag in ["head", "script", "style", "noscript", "svg"] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Blokkelementer blir avsnittsskift.
        let blockPattern = "</?(" + blockTags.joined(separator: "|") + ")(\\s[^>]*)?/?>"
        text = text.replacingOccurrences(of: blockPattern, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        // Fjern resten av taggene.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        // Rydd i mellomrom.
        text = text.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func paragraphs(from html: String) -> [String] {
        plainText(from: html)
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "shy": "",
        "aelig": "æ", "oslash": "ø", "aring": "å", "AElig": "Æ", "Oslash": "Ø", "Aring": "Å",
        "eacute": "é", "egrave": "è", "auml": "ä", "ouml": "ö", "uuml": "ü", "copy": "©",
    ]

    public static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            let char = string[index]
            if char == "&", let semicolon = string[index...].prefix(12).firstIndex(of: ";") {
                let name = String(string[string.index(after: index)..<semicolon])
                if let decoded = decodeEntity(name) {
                    result += decoded
                    index = string.index(after: semicolon)
                    continue
                }
            }
            result.append(char)
            index = string.index(after: index)
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[name]
    }

    /// Escaper tekst for bruk i HTML.
    public static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
