# Reader

En Kindle-lignende app for iPhone, iPad og Mac. Den samler egne e-bøker, lydbøker og lagrede artikler med bøker fra åpne bibliotek, kan lese all tekst høyt, og husker hvor du er på tvers av enheter.

## Kom i gang (macOS)

1. Installer Xcode fra App Store og [Homebrew](https://brew.sh).
2. Installer XcodeGen: `brew install xcodegen`
3. Generer prosjektet og åpne det:
   ```sh
   xcodegen
   open Reader.xcodeproj
   ```
4. Velg skjemaet `Reader_macOS` eller `Reader_iOS`, velg teamet ditt under *Signing & Capabilities* (gratis Apple-ID holder), og trykk Run.

Kjør `xcodegen` på nytt hver gang `project.yml` endres eller filer legges til. Selve prosjektfilen er ikke sjekket inn.

### På iPhone med gratis Apple-ID

Appen må installeres på nytt hver 7. dag. Koble til telefonen og trykk Run i Xcode, eller bruk [SideStore](https://sidestore.io) for automatisk fornyelse. Data i appen beholdes.

## Struktur

| Mappe | Innhold |
| --- | --- |
| `App/` | App-inngangen, felles for iOS og macOS |
| `Packages/ReaderKit/` | All logikk og alle skjermbilder (SwiftUI, SwiftData) |
| `project.yml` | XcodeGen-oppsett for appen |
| `.github/workflows/ci.yml` | Tester pakken og bygger begge appene ved hver push |

## Tester

```sh
swift test --package-path Packages/ReaderKit
```
