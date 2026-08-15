import SwiftUI

/// App-level preferences and server diagnostics.
struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var downloads: TrackDownloadStore
    @EnvironmentObject private var auth: AuthSessionStore
    @AppStorage("prefersLightAppearance") private var prefersLightAppearance = false
    @AppStorage(WelcomeStorage.completedKey) private var hasCompletedWelcome = false

    var body: some View {
        List {
            Section("Appearance") {
                Toggle(isOn: $prefersLightAppearance) {
                    Label("Light Appearance", systemImage: "sun.max.fill")
                }
                .accessibilityIdentifier("lightAppearanceToggle")
            }

            Section("Connection") {
                NavigationLink {
                    ServerSettingsView()
                } label: {
                    HStack(spacing: 14) {
                        ServerConnectionStatusIcon(state: catalog.connectionState)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(connectionTitle)
                                .font(.headline)
                            Text(catalog.serverURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("serverSettings")
            }

            if let account = auth.account {
                Section("Account") {
                    LabeledContent("Name", value: account.displayName)
                    LabeledContent("Username", value: account.username)
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        catalog.resetForLogout()
                        auth.logout()
                    }
                }
            }

            Section("Library portability") {
                NavigationLink {
                    OpenChordArchiveView()
                } label: {
                    Label("OpenChord Archive", systemImage: "archivebox.fill")
                }
                .accessibilityIdentifier("openChordArchiveSettings")
            }

            Section("Offline") {
                NavigationLink {
                    DownloadStorageView()
                } label: {
                    LabeledContent {
                        Text(downloads.downloadedBytes, format: .byteCount(style: .file))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Downloaded Music", systemImage: "arrow.down.circle.fill")
                    }
                }
                .accessibilityIdentifier("downloadStorageSettings")
            }

            Section {
                Button("Replay Introduction", systemImage: "sparkles.rectangle.stack") {
                    hasCompletedWelcome = false
                }
                .accessibilityIdentifier("replayIntroduction")

                LabeledContent("Version", value: appVersion)
            } header: {
                Text("About")
            } footer: {
                Text("OpenChord plays music from your self-hosted server.")
            }
        }
        .navigationTitle("Settings")
    }

    private var connectionTitle: String {
        switch catalog.connectionState {
        case .unknown: "Server not checked"
        case .connecting: "Checking server…"
        case .connected: "Server connected"
        case .unavailable: "Server unavailable"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

private struct DownloadStorageView: View {
    @EnvironmentObject private var downloads: TrackDownloadStore
    @State private var isConfirmingRemoval = false

    var body: some View {
        List {
            Section {
                LabeledContent("Tracks", value: "\(downloads.downloadedTrackCount)")
                LabeledContent(
                    "Storage Used",
                    value: downloads.downloadedBytes.formatted(.byteCount(style: .file))
                )
            }

            Section {
                Button("Remove All Downloads", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .disabled(downloads.downloadedTrackCount == 0)
            } footer: {
                Text("Music remains in your library and can be downloaded again.")
            }
        }
        .navigationTitle("Downloaded Music")
        .confirmationDialog(
            "Remove All Downloads?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove All Downloads", role: .destructive) {
                try? downloads.removeAllDownloads()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Semantic server state used by the Settings connection row.
private struct ServerConnectionStatusIcon: View {
    let state: CatalogStore.ConnectionState

    var body: some View {
        Group {
            switch state {
            case .unknown:
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
            case .connecting:
                ProgressView()
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.title2)
        .frame(width: 32, height: 32)
    }
}
