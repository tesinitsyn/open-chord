import CryptoKit
import SwiftUI
import UIKit

/// Square album artwork that falls back to a deterministic gradient placeholder.
///
/// Remote loading failures intentionally leave the placeholder visible instead
/// of exposing a broken-image state to the user.
struct ArtworkView: View {
    let style: ArtworkStyle
    var cornerRadius: CGFloat = 24
    @State private var remoteImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                fallback(side: side)

                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if style.remoteURL != nil {
                    ProgressView()
                        .tint(.white.opacity(0.8))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: style.remoteURL) {
            remoteImage = nil
            guard
                let remoteURL = style.remoteURL,
                let data = await ArtworkDataCache.shared.data(for: remoteURL),
                !Task.isCancelled
            else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                remoteImage = UIImage(data: data)
            }
        }
    }

    private func fallback(side: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: style.colors.map(\.swiftUIColor),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: side * 0.72, height: side * 0.72)
                .blur(radius: side * 0.008)
                .offset(x: side * 0.27, y: -side * 0.29)

            // Lazy containers briefly measure off-screen cells at zero. Avoid
            // asking SF Symbols for a zero-point glyph, which emits CoreUI
            // diagnostics on iOS 26.
            if side >= 1 {
                Image(systemName: style.symbol)
                    .font(.system(size: side * 0.23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

/// Client-owned memory and disk cache for remote album artwork.
///
/// Artwork endpoints are not required to send HTTP cache headers, so relying on
/// `URLCache` alone causes the same images to be fetched after every launch.
private actor ArtworkDataCache {
    static let shared = ArtworkDataCache()

    private var memory: [URL: Data] = [:]
    private let directory: URL

    init(fileManager: FileManager = .default) {
        directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL) async -> Data? {
        if let cached = memory[url] {
            return cached
        }

        let fileURL = directory.appendingPathComponent(cacheKey(for: url))
        if let cached = try? Data(contentsOf: fileURL) {
            memory[url] = cached
            return cached
        }

        guard
            let (data, response) = try? await URLSession.shared.data(from: url),
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            UIImage(data: data) != nil
        else { return nil }

        memory[url] = data
        try? data.write(to: fileURL, options: .atomic)
        return data
    }

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension ArtworkColor {
    var swiftUIColor: Color {
        switch self {
        case .violet: .purple
        case .indigo: .indigo
        case .blue: .blue
        case .cyan: .cyan
        case .mint: .mint
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }
}

/// Playback-oriented formatting helpers for durations expressed in seconds.
extension TimeInterval {
    var playbackTime: String {
        guard isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(self))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
