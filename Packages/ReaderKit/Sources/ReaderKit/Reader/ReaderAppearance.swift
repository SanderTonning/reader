import SwiftUI

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    public var id: String { rawValue }

    var name: String {
        switch self {
        case .light: "Lys"
        case .sepia: "Sepia"
        case .dark: "Mørk"
        }
    }

    var background: String {
        switch self {
        case .light: "#ffffff"
        case .sepia: "#f4ecd8"
        case .dark: "#1c1c1e"
        }
    }

    var foreground: String {
        switch self {
        case .light: "#1c1c1e"
        case .sepia: "#5b4636"
        case .dark: "#e5e5e7"
        }
    }

    var link: String {
        switch self {
        case .light: "#0a5ad4"
        case .sepia: "#8a4b14"
        case .dark: "#6cb4ff"
        }
    }

    var backgroundColor: Color { Color(hex: background) }
    var foregroundColor: Color { Color(hex: foreground) }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Utseendet i leseren, lagret per enhet.
struct ReaderAppearance: Equatable {
    var theme: ReaderTheme
    var fontScale: Double
    var lineHeight: Double
    var serif: Bool

    /// JavaScript-objekt som sendes til readerApply() i nettleseren.
    var javaScriptObject: String {
        let font = serif ? "'Iowan Old Style', 'Palatino', 'Georgia', serif" : "-apple-system, 'Helvetica Neue', sans-serif"
        return """
        {bg:"\(theme.background)",fg:"\(theme.foreground)",link:"\(theme.link)",size:\(Int(fontScale * 100)),lineHeight:\(lineHeight),font:"\(font)"}
        """
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("reader.theme") private var theme = ReaderTheme.light.rawValue
    @AppStorage("reader.fontScale") private var fontScale = 1.0
    @AppStorage("reader.lineHeight") private var lineHeight = 1.5
    @AppStorage("reader.serif") private var serif = true
    @AppStorage("reader.tapToLookUp") private var tapToLookUp = true

    var body: some View {
        Form {
            Picker("Tema", selection: $theme) {
                ForEach(ReaderTheme.allCases) { Text($0.name).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button { fontScale = max(0.7, fontScale - 0.1) } label: { Image(systemName: "textformat.size.smaller") }
                Spacer()
                Text("\(Int((fontScale * 100).rounded())) %").monospacedDigit()
                Spacer()
                Button { fontScale = min(2.5, fontScale + 0.1) } label: { Image(systemName: "textformat.size.larger") }
            }
            .buttonStyle(.borderless)
            Picker("Linjeavstand", selection: $lineHeight) {
                Text("Tett").tag(1.3)
                Text("Normal").tag(1.5)
                Text("Luftig").tag(1.8)
            }
            Toggle("Skrift med seriffer", isOn: $serif)
            Toggle("Trykk på ord for oppslag", isOn: $tapToLookUp)
        }
        .frame(minWidth: 300, minHeight: 280)
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
