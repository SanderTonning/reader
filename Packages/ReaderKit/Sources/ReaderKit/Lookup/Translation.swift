import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Viser Apples oversettelseskort for en tekst (iOS 17.4 / macOS 14.4 og nyere).
struct TranslationPresenter: ViewModifier {
    @Binding var isPresented: Bool
    var text: String

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 17.4, macOS 14.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
/// Oversetter en hel tekst avsnitt for avsnitt med Apples Translation-rammeverk (gratis, på enheten).
@available(iOS 18.0, macOS 15.0, *)
struct FullTextTranslationView: View {
    let title: String
    let paragraphs: [String]
    @State private var target = Locale.Language(identifier: Locale.current.language.languageCode?.identifier ?? "nb")
    @State private var configuration: TranslationSession.Configuration?
    @State private var translated: [String] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private static let targets: [(String, String)] = [
        ("nb", "Norsk"), ("en", "Engelsk"), ("sv", "Svensk"), ("da", "Dansk"),
        ("de", "Tysk"), ("fr", "Fransk"), ("es", "Spansk"), ("it", "Italiensk"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Oversett til", selection: $target) {
                        ForEach(Self.targets, id: \.0) { code, name in
                            Text(name).tag(Locale.Language(identifier: code))
                        }
                    }
                    Button(isWorking ? "Oversetter …" : "Oversett") { translate() }
                        .disabled(isWorking || paragraphs.isEmpty)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(Array(translated.enumerated()), id: \.offset) { _, text in
                    Text(text).textSelection(.enabled)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
            .translationTask(configuration) { session in
                do {
                    let requests = paragraphs.enumerated().map {
                        TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                    }
                    let responses = try await session.translations(from: requests)
                    let sorted = responses.sorted { Int($0.clientIdentifier ?? "0") ?? 0 < Int($1.clientIdentifier ?? "0") ?? 0 }
                    translated = sorted.map(\.targetText)
                } catch {
                    errorMessage = "Oversettelsen feilet: \(error.localizedDescription)"
                }
                isWorking = false
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func translate() {
        errorMessage = nil
        translated = []
        isWorking = true
        if configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        }
    }
}
#endif
