import AVFoundation
import Foundation
import Observation
import SwiftData

/// Qovluğu tarayıb SwiftData-ya yazır. Fayllar köçürülmür.
///
/// Ağır iş (metadata oxunması) arxa planda gedir, yazma isə model context-in
/// aktorunda — ona görə tarama iki mərhələlidir: əvvəl disk, sonra baza.
@MainActor
@Observable
final class LibraryImporter {

    struct Progress: Equatable, Sendable {
        var processed = 0
        var total = 0
        var currentFilename = ""
        var unsupported = 0
        var isFinished = false
    }

    private(set) var progress = Progress()
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// İstifadəçi Files-dan qovluq seçəndən sonra çağırılır.
    func importFolder(at url: URL) async throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw PlaybackError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let folderBookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let folder = LibraryFolder(displayName: url.lastPathComponent, bookmark: folderBookmark)
        context.insert(folder)

        let candidates = Self.scanFiles(in: url)
        progress = Progress(processed: 0, total: candidates.count, currentFilename: "", unsupported: 0)

        for fileURL in candidates {
            progress.currentFilename = fileURL.lastPathComponent

            let ext = fileURL.pathExtension.lowercased()
            guard EngineRouter.isSupported(fileExtension: ext) else {
                progress.unsupported += 1
                progress.processed += 1
                continue
            }

            if let item = await Self.makeItem(from: fileURL) {
                item.folder = folder
                context.insert(item)
            }
            progress.processed += 1

            // Hər 50 faylda bir yazırıq ki, böyük kataloqda yaddaş şişməsin.
            if progress.processed % 50 == 0 { try? context.save() }
        }

        folder.lastScannedAt = .now
        progress.isFinished = true
        try context.save()
    }

    /// Qovluğu rekursiv gəzir, gizli faylları atır.
    private static func scanFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            guard !url.pathExtension.isEmpty else { continue }
            results.append(url)
        }
        return results
    }

    /// Bir faylın metadatasını oxuyur. Oxuna bilməsə də element yaradılır —
    /// fayl adı başlıq kimi işlədilir, çünki oxunmayan metadata faylı kitabxanadan
    /// silmək üçün səbəb deyil.
    private static func makeItem(from url: URL) async -> MediaItem? {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
        let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)

        var title = url.deletingPathExtension().lastPathComponent
        var artist: String?
        var album: String?
        var duration: Double = 0
        var artwork: Data?
        var pixelHeight: Int?
        var codec: String?

        // AVFoundation MKV oxumur; belə fayllarda metadata VLC açılanda gəlir.
        let asset = AVURLAsset(url: url)
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            duration = seconds
        }
        if let metadata = try? await asset.load(.commonMetadata) {
            for entry in metadata {
                switch entry.commonKey {
                case .commonKeyTitle:
                    // `try?` + optional dəyər iç-içə optional verir, ona görə düzləşdirilir.
                    if let value = (try? await entry.load(.stringValue)) ?? nil, !value.isEmpty {
                        title = value
                    }
                case .commonKeyArtist:
                    artist = (try? await entry.load(.stringValue)) ?? nil
                case .commonKeyAlbumName:
                    album = (try? await entry.load(.stringValue)) ?? nil
                case .commonKeyArtwork:
                    artwork = (try? await entry.load(.dataValue)) ?? nil
                default:
                    break
                }
            }
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                pixelHeight = Int(abs(size.height))
            }
            if let descriptions = try? await track.load(.formatDescriptions),
               let description = descriptions.first {
                codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
            }
        }

        return MediaItem(
            title: title,
            artist: artist,
            album: album,
            kind: EngineRouter.kind(forFileExtension: ext),
            engine: EngineRouter.engine(forFileExtension: ext),
            filename: filename,
            fileExtension: ext,
            fileSize: size,
            duration: duration,
            bookmark: bookmark,
            artworkData: artwork,
            videoCodec: codec,
            pixelHeight: pixelHeight
        )
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
