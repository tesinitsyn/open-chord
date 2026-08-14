import PhotosUI
import SwiftUI
import UIKit

/// Full creation flow for playlist identity and optional custom artwork.
struct CreatePlaylistView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var playlistDescription = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var artworkImage: UIImage?
    @State private var artworkData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                artworkPicker
                    .padding(.top, 12)

                VStack(spacing: 14) {
                    glassTextField
                    glassDescriptionField
                }

                createButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("New Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .disabled(isSaving)
        .overlay {
            if isSaving {
                ProgressView("Creating Playlist…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .task(id: selectedPhoto) {
            guard
                let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { return }
            artworkImage = image
            artworkData = image.jpegData(compressionQuality: 0.86)
        }
        .alert(
            "Could Not Create Playlist",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        Group {
            if let artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkView(
                    style: ArtworkStyle(
                        symbol: "music.note.list",
                        colors: [.indigo, .violet]
                    ),
                    cornerRadius: 28
                )
            }
        }
        .frame(width: 248, height: 248)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var artworkPicker: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                artworkContent

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                }
                .openChordGlassButton()
                .offset(x: 8, y: 8)
            }

            Text(artworkImage == nil ? "Add artwork" : "Tap to change artwork")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var glassTextField: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("Playlist name", text: $name)
                .font(.body.weight(.medium))
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .openChordGlass(cornerRadius: 22)
    }

    private var glassDescriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Description", systemImage: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
                Text("\(playlistDescription.count)/500")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        playlistDescription.count > 500 ? Color.red : Color.secondary
                    )
            }

            TextEditor(text: $playlistDescription)
                .font(.body)
                .frame(minHeight: 108)
                .scrollContentBackground(.hidden)
        }
        .padding(18)
        .openChordGlass(cornerRadius: 22)
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 9) {
                if isSaving {
                    ProgressView()
                } else {
                    Image(systemName: "plus")
                }
                Text(isSaving ? "Creating…" : "Create Playlist")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .openChordProminentGlassButton()
        .disabled(!canCreate)
    }

    private var canCreate: Bool {
        !isSaving
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && playlistDescription.count <= 500
    }

    private func create() {
        isSaving = true
        let creation = PlaylistCreation(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            artworkData: artworkData
        )
        Task {
            do {
                try await catalog.createPlaylist(creation)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
