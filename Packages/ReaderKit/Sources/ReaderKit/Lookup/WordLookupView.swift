import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
import CoreServices
#endif

/// Et ord brukeren har trykket på, med setningen rundt.
public struct WordLookup: Identifiable, Hashable {
    public var id: String { word + "|" + context }
    public var word: String
    public var context: String

    public init(word: String, context: String) {
        self.word = word
        self.context = context
    }
}

/// Kort med ordbokbetydning (systemordboka) og oversettelse (Apple Oversett). Alt er gratis og på enheten.
struct WordLookupView: View {
    let lookup: WordLookup
    @State private var showDictionary = false
    @State private var translateWord = false
    @State private var translateContext = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(lookup.word)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                }
                Section("Betydning") {
                    #if os(iOS)
                    if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: lookup.word) {
                        Button("Vis i ordboka") { showDictionary = true }
                    } else {
                        Text("Ingen ordbok har dette ordet. Last ned flere ordbøker under Innstillinger › Generelt › Ordbok.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #else
                    if let definition = Self.macDefinition(for: lookup.word) {
                        Text(definition)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        Text("Fant ingen definisjon i Ordbok-appen.")
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }
                Section("Oversettelse") {
                    Button {
                        translateWord = true
                    } label: {
                        Label("Oversett ordet", systemImage: "translate")
                    }
                    .modifier(TranslationPresenter(isPresented: $translateWord, text: lookup.word))

                    if !lookup.context.isEmpty {
                        Button {
                            translateContext = true
                        } label: {
                            Label("Oversett setningen", systemImage: "text.bubble")
                        }
                        .modifier(TranslationPresenter(isPresented: $translateContext, text: lookup.context))
                        Text(lookup.context)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ordoppslag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showDictionary) {
            DictionaryView(term: lookup.word)
                .ignoresSafeArea()
        }
        #endif
        .frame(minWidth: 320, minHeight: 360)
    }

    #if os(macOS)
    static func macDefinition(for word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() else { return nil }
        return definition as String
    }
    #endif
}

#if os(iOS)
struct DictionaryView: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
#endif
