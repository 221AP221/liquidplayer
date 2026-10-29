import SwiftUI

/// Now Playing menyusundan: faylın texniki məlumatı.
struct FileInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("info.title", item.title)
                    if let artist = item.artist, !artist.isEmpty { row("info.artist", artist) }
                    if let album = item.album, !album.isEmpty { row("info.album", album) }
                }

                Section {
                    row("info.filename", item.filename)
                    if let folder = item.folder {
                        row("info.location", [folder.displayName, item.relativePath]
                            .compactMap { $0 }
                            .joined(separator: " / "))
                    }
                    row("info.format", item.fileExtension.uppercased())
                    row("info.size", item.fileSize.formatted(.byteCount(style: .file)))
                    row("info.duration", item.duration.timeLabel)
                    if let height = item.pixelHeight, height > 0 { row("info.resolution", "\(height)p") }
                    if let codec = item.videoCodec, !codec.isEmpty { row("info.codec", codec) }
                    row("info.engine", item.engine == .vlc ? "VLCKit" : "AVFoundation")
                }

                Section {
                    row("info.added", item.addedAt.formatted(date: .abbreviated, time: .shortened))
                    if let lastPlayed = item.lastPlayedAt {
                        row("info.lastPlayed", lastPlayed.formatted(date: .abbreviated, time: .shortened))
                    }
                    row("info.progress", item.progress.formatted(.percent.precision(.fractionLength(0))))
                    if !item.bookmarks.isEmpty { row("info.bookmarks", "\(item.bookmarks.count)") }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.base)
            .navigationTitle("menu.fileInfo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
