import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var sync = SyncEngine.shared
    @State private var showFolderPicker = false
    @State private var deviceName = DeviceInfo.name

    var body: some View {
        Form {
            Section {
                if let folder = sync.folderName {
                    LabeledContent("Mappe", value: folder)
                    Button {
                        Task { await sync.sync(context: context) }
                    } label: {
                        HStack {
                            Text("Synk nå")
                            if sync.isSyncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing)
                    if let last = sync.lastSync {
                        LabeledContent("Sist synket") { Text(last, style: .relative) }
                    }
                    Toggle("Del egne filer mellom enheter", isOn: $sync.shareOwnFiles)
                    Button("Velg en annen mappe") { showFolderPicker = true }
                    Button("Slå av synk", role: .destructive) { sync.clearFolder() }
                } else {
                    Button("Velg synkmappe") { showFolderPicker = true }
                }
                if let status = sync.status {
                    Text(status).foregroundStyle(.red).font(.footnote)
                }
            } header: {
                Text("Synk mellom enheter")
            } footer: {
                Text("Velg samme mappe i iCloud Drive (for eksempel iCloud Drive › Reader) på alle enhetene dine. Bibliotek, bokmerker og hvor langt du har kommet synkes gratis, uten konto eller server. Bøker fra åpne bibliotek lastes ned på nytt; egne filer kopieres til mappen hvis du slår det på.")
            }

            Section("Denne enheten") {
                TextField("Navn", text: $deviceName)
                    .onSubmit { DeviceInfo.name = deviceName }
                    .onChange(of: deviceName) { DeviceInfo.name = deviceName }
            }

            Section("Leser") {
                AppearanceSettingsView()
            }

            Section("Om") {
                LabeledContent("Versjon", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("Artikler hentes med Mozilla Readability (Apache 2.0). Bøker fra Project Gutenberg og LibriVox er i offentlig eie. Ordbok, oversettelse og stemmer kommer fra Apple og kjører på enheten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Innstillinger")
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                sync.setFolder(url)
                Task { await sync.sync(context: context) }
            }
        }
    }
}
