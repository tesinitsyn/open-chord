import SwiftUI

enum WelcomeStorage {
    static let completedKey = "hasCompletedWelcome"
}

/// A one-time introduction that explains OpenChord before server setup begins.
struct WelcomeView: View {
    private static let pages = WelcomePage.all

    let onComplete: () -> Void

    @State private var selection = 0
    @State private var glowMoves = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                TabView(selection: $selection) {
                    ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                        WelcomePageView(page: page, isVisible: selection == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                glowMoves = true
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            Circle()
                .fill(currentPage.palette.backgroundGlow)
                .frame(width: 420, height: 420)
                .blur(radius: 18)
                .scaleEffect(glowMoves ? 1.12 : 0.94)
                .offset(x: glowMoves ? 145 : 185, y: glowMoves ? -285 : -325)

            Circle()
                .fill(currentPage.palette.secondaryGlow)
                .frame(width: 360, height: 360)
                .blur(radius: 14)
                .scaleEffect(glowMoves ? 0.9 : 1.08)
                .offset(x: glowMoves ? -170 : -205, y: glowMoves ? 305 : 350)
        }
        .animation(.smooth(duration: 0.75), value: selection)
    }

    private var header: some View {
        HStack {
            Label("OpenChord", systemImage: "waveform")
                .font(.headline.weight(.bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(currentPage.palette.accent)

            Spacer()

            if selection < Self.pages.count - 1 {
                Button("Skip", action: onComplete)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .frame(height: 62)
    }

    private var footer: some View {
        VStack(spacing: 22) {
            HStack(spacing: 7) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selection ? currentPage.palette.accent : Color.secondary.opacity(0.22))
                        .frame(width: index == selection ? 24 : 7, height: 7)
                        .animation(.snappy, value: selection)
                }
            }
            .accessibilityHidden(true)

            Button {
                advance()
            } label: {
                HStack(spacing: 10) {
                    Text(selection == Self.pages.count - 1 ? "Connect Your Server" : "Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
            }
            .buttonStyle(WelcomeButtonStyle(palette: currentPage.palette))
            .accessibilityIdentifier("welcomeContinue")
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
    }

    private var currentPage: WelcomePage {
        Self.pages[selection]
    }

    private func advance() {
        guard selection < Self.pages.count - 1 else {
            onComplete()
            return
        }

        withAnimation(.smooth) {
            selection += 1
        }
    }
}

private struct WelcomePageView: View {
    let page: WelcomePage
    let isVisible: Bool

    var body: some View {
        VStack(spacing: 34) {
            Spacer(minLength: 12)

            WelcomeIllustration(kind: page.illustration, palette: page.palette, isVisible: isVisible)
                .frame(maxWidth: .infinity)
                .frame(height: 278)

            VStack(spacing: 14) {
                Text(page.eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(page.palette.accent)

                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.9)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 330)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            .opacity(isVisible ? 1 : 0.55)
            .offset(y: isVisible ? 0 : 10)
            .animation(.smooth.delay(0.08), value: isVisible)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeIllustration: View {
    let kind: WelcomePage.Illustration
    let palette: WelcomePalette
    let isVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 30, y: 18)

            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .fill(palette.cardTint)

            switch kind {
            case .library:
                library
            case .player:
                player
            case .offline:
                offline
            case .people:
                people
            }
        }
        .frame(maxWidth: 360)
        .scaleEffect(isVisible ? 1 : 0.92)
        .rotation3DEffect(.degrees(isVisible ? 0 : 5), axis: (x: 0, y: 1, z: 0))
        .animation(.bouncy(duration: 0.65), value: isVisible)
    }

    private var library: some View {
        ZStack {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        index == 0
                            ? AnyShapeStyle(palette.gradient)
                            : AnyShapeStyle(palette.accent.opacity(0.13 + Double(index) * 0.04))
                    )
                    .frame(width: 178, height: 178)
                    .overlay {
                        if index == 0 {
                            Image(systemName: "waveform")
                                .font(.system(size: 54, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                        }
                    }
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * 42, y: CGFloat(index) * -7)
            }

            Image(systemName: "server.rack")
                .font(.title2.weight(.semibold))
                .padding(16)
                .background(.thickMaterial, in: Circle())
                .offset(x: 112, y: 102)
        }
    }

    private var player: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(palette.gradient)
                .frame(width: 172, height: 172)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }

            HStack(spacing: 30) {
                Image(systemName: "shuffle")
                Image(systemName: "backward.fill")
                Image(systemName: "pause.fill")
                    .font(.title2)
                Image(systemName: "forward.fill")
                Image(systemName: "repeat")
            }
            .font(.headline)
            .foregroundStyle(palette.accent)
        }
    }

    private var offline: some View {
        ZStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 132, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.accent)

            HStack(spacing: 6) {
                ForEach([18, 34, 52, 30, 44, 22], id: \.self) { height in
                    Capsule()
                        .fill(palette.gradient)
                        .frame(width: 8, height: CGFloat(height))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 17)
            .background(.thickMaterial, in: Capsule())
            .offset(y: 105)
        }
    }

    private var people: some View {
        ZStack {
            Circle()
                .fill(palette.gradient)
                .frame(width: 154, height: 154)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 66))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }

            personBadge(icon: "person.fill", x: -102, y: 74)
            personBadge(icon: "figure.child", x: 105, y: 72)
            personBadge(icon: "person.fill", x: 98, y: -80)
        }
    }

    private func personBadge(icon: String, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.title2.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(width: 66, height: 66)
            .background(.thickMaterial, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            .offset(x: x, y: y)
    }
}

private struct WelcomePage {
    enum Illustration {
        case library
        case player
        case offline
        case people
    }

    let eyebrow: String
    let title: String
    let message: String
    let illustration: Illustration
    let palette: WelcomePalette

    static let all = [
        WelcomePage(
            eyebrow: "Your collection",
            title: "Your music stays yours.",
            message: "OpenChord streams your own library from a server you control. No catalog can take it away.",
            illustration: .library,
            palette: .monochrome
        ),
        WelcomePage(
            eyebrow: "A real music player",
            title: "Built for listening.",
            message:
                "Shape the queue, shuffle, repeat, follow lyrics and move through albums without breaking the flow.",
            illustration: .player,
            palette: .monochrome
        ),
        WelcomePage(
            eyebrow: "Ready anywhere",
            title: "Take it offline.",
            message:
                "Download the tracks you love. Artwork and music stay ready when your server—or the internet—isn't.",
            illustration: .offline,
            palette: .monochrome
        ),
        WelcomePage(
            eyebrow: "One server, your choice",
            title: "Just you. Or everyone.",
            message: "Keep a private library or give each family member their own account, history and space.",
            illustration: .people,
            palette: .monochrome
        ),
    ]
}

private struct WelcomePalette {
    let accent: Color
    let companion: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, companion], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var backgroundGlow: Color { accent.opacity(0.045) }
    var secondaryGlow: Color { companion.opacity(0.035) }
    var cardTint: Color { accent.opacity(0.018) }

    static let monochrome = WelcomePalette(
        accent: .primary,
        companion: .secondary
    )
}

private struct WelcomeButtonStyle: ButtonStyle {
    let palette: WelcomePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(palette.gradient, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.08 : 0.18),
                radius: configuration.isPressed ? 5 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    WelcomeView {}
        .preferredColorScheme(.dark)
}
