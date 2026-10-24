# Reader – instrukser for Claude

Native SwiftUI-app for iOS 17+ og macOS 14+. Hobbyprosjekt: **ingen kostnader** (ingen betalte API-er, ingen betalt Apple-konto, offentlig repo). Spesifikasjon: https://claude.ai/artifact/778ao1CMrrWZGCpZEVQeHk

## Oppsett
- XcodeGen: `project.yml` genererer `Reader.xcodeproj` (ikke sjekket inn). Mål: `Reader_iOS`, `Reader_macOS`.
- All kode bor i `Packages/ReaderKit` (SwiftData-modeller, tjenester, SwiftUI-visninger). `App/` er bare inngangen.
- Ingen Swift-verktøykjede i skyøkter: CI (`.github/workflows/ci.yml`, macOS-runner) er kompilatoren. Push og les feilene derfra.

## Kommandoer (på Mac)
- `xcodegen && open Reader.xcodeproj`
- `swift test --package-path Packages/ReaderKit`
- `xcodebuild build -project Reader.xcodeproj -scheme Reader_iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | xcbeautify --quiet`

## Tokenbruk (se skill reader-token-economy)
- Haiku til søk og småting, Sonnet til vanlig implementering, Opus til arkitektur og vanskelig feilsøking.
- Én tråd eller økt per oppgave eller PR. Overlevering via spesifikasjonen, prosjektminnet og denne filen.
- Grep før Read, og les bare relevante linjer. Les aldri `*.xcodeproj`, `.build/`, `DerivedData/` eller `Package.resolved`.
- Filtrer bygg- og CI-logger ned til `error:`-linjer. Ikke lim inn hele logger.

## Konvensjoner
- UI-tekst på norsk bokmål. Kode og identifikatorer på engelsk.
- Posisjon lagres som `ReadingPosition` (JSON) på `Book` og `Bookmark`, og det er den som synkes.
- Plattformforskjeller håndteres med `#if os(iOS)` / `#if os(macOS)` i ReaderKit.
