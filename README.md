# OpenChord

## Portable library archives

Settings → **OpenChord Archive** connects to the configured server to:

- prepare and share a complete `.openchord` library archive;
- export an individual playlist with its dependencies;
- choose an archive from Files and restore it on the server.

Downloads use a temporary file and imports construct a disk-backed multipart
request, keeping large archives out of the app's in-memory state.

OpenChord is an open-source SwiftUI client for a self-hosted music server. It
keeps the music library, listening history, and synchronized lyrics under the
listener's control.

## Run on a local network

1. Start the backend from the sibling `open-chord-back` repository:

   ```sh
   ./scripts/lan-up.sh
   ```

2. Open `OpenChord.xcodeproj`, select an iPhone running iOS 17 or later, and
   press Run.
3. Make sure the Mac and iPhone are connected to the same local network.
4. In OpenChord, tap the server button and enter the address printed by the
   backend script, for example `http://192.168.1.20:8080`.
5. Allow local-network access when iOS asks for permission.

The server includes a small demo album, **Afterglow**, so the catalog, audio
streaming, byte-range requests, and synchronized lyrics work immediately.
Simulator builds default to `http://localhost:8080`.

## Project structure

- `Domain` contains UI-independent domain models.
- `Data` contains the GraphQL client and catalog state.
- `Playback` owns the shared `AVPlayer`-based playback engine.
- `UI` groups views by user journey.

The client intentionally re-anchors media links to the configured server
address. This keeps streaming functional on a physical iPhone even if the
backend was started with a loopback public URL.

Server artwork is loaded asynchronously with a generated fallback for missing
or unavailable images. Tracks can be downloaded individually or by album; the
client stores them in Application Support and automatically prefers the local
copy during playback.

## Engineering principles

OpenChord is developed as a production-quality application from the start.
Visual quality, clear architecture, automated tests, accessibility, and CI/CD
are product requirements rather than deferred cleanup.

See [`docs/ENGINEERING_PRINCIPLES.md`](docs/ENGINEERING_PRINCIPLES.md) for the
full engineering standard.

## Tests and CI

The project has separate unit- and UI-test targets. Every pull request runs
formatting, static analysis, build, unit-test, and UI-test checks in GitHub
Actions.

Local commands and the CI setup are documented in
[`docs/TESTING.md`](docs/TESTING.md).
