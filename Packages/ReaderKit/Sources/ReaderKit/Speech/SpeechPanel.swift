import AVFoundation
import SwiftUI

/// Panel nederst i leseren mens teksten leses høyt. Setningen som leses, markeres.
struct SpeechPanel: View {
    @ObservedObject var speech: SpeechReader
    var onClose: () -> Void
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Text(highlightedParagraph)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 110)

            HStack(spacing: 28) {
                Button { speech.previousParagraph() } label: { Image(systemName: "backward.fill") }
                Button { speech.togglePause() } label: {
                    Image(systemName: speech.isSpeaking && !speech.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                }
                Button { speech.nextParagraph() } label: { Image(systemName: "forward.fill") }
                Button { showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .popover(isPresented: $showSettings) { SpeechSettingsView(speech: speech) }
                Button(action: onClose) { Image(systemName: "xmark.circle") }
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var highlightedParagraph: AttributedString {
        let paragraph = speech.paragraphs[safe: speech.paragraphIndex] ?? ""
        var attributed = AttributedString(paragraph)
        if let range = speech.spokenRange,
           let swiftRange = Range(range, in: paragraph),
           let lower = AttributedString.Index(swiftRange.lowerBound, within: attributed),
           let upper = AttributedString.Index(swiftRange.upperBound, within: attributed) {
            attributed[lower..<upper].backgroundColor = .yellow.opacity(0.45)
            attributed[lower..<upper].font = .callout.bold()
        }
        return attributed
    }
}

struct SpeechSettingsView: View {
    @ObservedObject var speech: SpeechReader

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Hastighet")
                Slider(value: $speech.rate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate, onEditingChanged: { editing in
                    if !editing { speech.restartCurrentWithNewSettings() }
                })
            }
            Picker("Stemme", selection: $speech.voiceIdentifier) {
                Text("Automatisk").tag(String?.none)
                ForEach(SpeechReader.voices(for: speech.language), id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(Optional(voice.identifier))
                }
            }
            .onChange(of: speech.voiceIdentifier) { speech.restartCurrentWithNewSettings() }
            Text("Last ned bedre stemmer gratis under Innstillinger › Tilgjengelighet › Opplest innhold › Stemmer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 300, minHeight: 240)
    }
}
