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
    var showsFallbackSymbol = true
    @State private var remoteImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                if let remoteImage {
                    Image(uiImage: remoteImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    fallback(side: side)

                    if style.remoteURL != nil {
                        ProgressView()
                            .tint(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: style.remoteURL) {
            guard
                let remoteURL = style.remoteURL,
                !Task.isCancelled
            else { return }

            let cacheURL = ArtworkDataCache.cacheIdentity(for: remoteURL)
            if let cached = DecodedArtworkCache.images.object(forKey: cacheURL as NSURL) {
                remoteImage = cached
                return
            }

            remoteImage = nil
            guard
                let data = await ArtworkDataCache.shared.data(for: remoteURL),
                !Task.isCancelled,
                let image = UIImage(data: data)
            else { return }

            DecodedArtworkCache.images.setObject(image, forKey: cacheURL as NSURL)

            withAnimation(.easeOut(duration: 0.2)) {
                remoteImage = image
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
            if showsFallbackSymbol, side >= 1 {
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
actor ArtworkDataCache {
    static let shared = ArtworkDataCache()

    private var memory: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let directory: URL
    private let session: URLSession

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        directory: URL? = nil
    ) {
        self.session = session
        self.directory =
            directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artwork", isDirectory: true)
        try? fileManager.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true
        )
    }

    func data(for url: URL) async -> Data? {
        let key = cacheKey(for: url)
        if let cached = memory[key] {
            return cached
        }

        let fileURL = directory.appendingPathComponent(key)
        if let cached = try? Data(contentsOf: fileURL) {
            memory[key] = cached
            return cached
        }

        if let request = inFlight[key] {
            return await request.value
        }

        let request = Task<Data?, Never> { [session] in
            guard
                let (data, response) = try? await session.data(from: url),
                let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode),
                UIImage(data: data) != nil
            else { return nil }
            return data
        }
        inFlight[key] = request
        let data = await request.value
        inFlight[key] = nil
        guard let data else { return nil }

        memory[key] = data
        try? data.write(to: fileURL, options: Data.WritingOptions.atomic)
        return data
    }

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(Self.cacheIdentity(for: url).absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated static func cacheIdentity(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = components.queryItems?.filter { $0.name != "access_token" }
        return components.url ?? url
    }
}

@MainActor
private enum DecodedArtworkCache {
    static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
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
