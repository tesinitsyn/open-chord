import SwiftUI

/// Application composition root for shared catalog, download, and playback state.
///
/// The long-lived objects are created once at the scene boundary so playback and
/// loaded catalog data survive navigation and modal presentation changes.
@main
struct OpenChordApp: App {
    @State private var player = PlaybackController()
    @StateObject private var catalog = CatalogStore()
    @StateObject private var downloads = TrackDownloadStore()
    @AppStorage("prefersLightAppearance") private var prefersLightAppearance = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .environmentObject(catalog)
                .environmentObject(downloads)
                .preferredColorScheme(prefersLightAppearance ? .light : .dark)
        }
    }
}
