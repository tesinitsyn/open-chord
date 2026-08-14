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
    @StateObject private var auth = AuthSessionStore()
    @AppStorage("prefersLightAppearance") private var prefersLightAppearance = false

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    RootView()
                } else {
                    AuthenticationView()
                }
            }
                .environment(player)
                .environmentObject(catalog)
                .environmentObject(downloads)
                .environmentObject(auth)
                .preferredColorScheme(prefersLightAppearance ? .light : .dark)
        }
    }
}
