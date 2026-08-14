import SwiftUI

/// App-level preferences and server diagnostics.
struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @AppStorage("prefersLightAppearance") private var prefersLightAppearance = false

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

            Section("Library portability") {
                NavigationLink {
                    OpenChordArchiveView()
                } label: {
                    Label("OpenChord Archive", systemImage: "archivebox.fill")
                }
                .accessibilityIdentifier("openChordArchiveSettings")
            }

            Section {
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
