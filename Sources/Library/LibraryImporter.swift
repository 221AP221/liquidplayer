import AVFoundation
import Foundation
import Observation
import SwiftData

/// Qovluğu tarayıb SwiftData-ya yazır və sonradan yeniləyir. Fayllar köçürülmür.
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
    /// Fon yenilənməsi gedirmi. Eyni anda ikinci tarama başlamır.
    private(set) var isRefreshing = false
    private var lastRefreshAt: Date?
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// İstifadəçi Files-dan qovluq seçəndən sonra çağırılır.
    /// Eyni qovluq artıq kitabxanadadırsa ikinci nüsxə yaranmır — sadəcə yenidən taranır.
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

        let folder: LibraryFolder
        if let existing = existingFolder(at: url) {
            folder = existing
            folder.bookmark = folderBookmark
            folder.hasAccess = true
        } else {
            folder = LibraryFolder(displayName: url.lastPathComponent, bookmark: folderBookmark)
            context.insert(folder)
        }

        await sync(folder, rootURL: url)
        try context.save()
    }

    /// Bütün qovluqları yenidən tarayır: yeni faylları əlavə edir, silinənləri
    /// `isMissing` işarələyir (oxunmuş yer və əlfəcinlər qalır), qayıdanları geri açır.
    ///
    /// App açılanda və ön plana qayıdanda çağırılır. `minimumInterval` tez-tez
    /// tətbiq dəyişdirəndə diskin boş yerə gəzilməməsi üçündür.
    func refreshAllFolders(minimumInterval: TimeInterval = 0) async {
        guard !isRefreshing else { return }
        if let lastRefreshAt, Date.now.timeIntervalSince(lastRefreshAt) < minimumInterval { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = .now
        }

        let folders = (try? context.fetch(FetchDescriptor<LibraryFolder>())) ?? []
        for folder in folders {
            await refresh(folder)
        }
        try? context.save()
    }

    // MARK: - Tarama

    private func refresh(_ folder: LibraryFolder) async {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else {
            markInaccessible(folder)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Bookmark silinmiş qovluğa da həll oluna bilər — yolun özünü yoxlayırıq.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            markInaccessible(folder)
            return
        }

        if isStale, let refreshed = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            folder.bookmark = refreshed
        }
        folder.hasAccess = true
        await sync(folder, rootURL: url)
    }

    /// İcazə itəndə fayllar gizlənir, amma silinmir — qovluq qayıdanda hər şey yerinə düşür.
    private func markInaccessible(_ folder: LibraryFolder) {
        folder.hasAccess = false
        for item in folder.items { item.isMissing = true }
    }

    /// Diskdəki vəziyyəti bazaya köçürür. Metadata yalnız yeni fayllar üçün oxunur,
    /// ona görə dəyişməyən böyük qovluğun yenilənməsi ucuzdur.
    private func sync(_ folder: LibraryFolder, rootURL: URL) async {
        let candidates = await Task.detached(priority: .utility) {
            Self.scanFiles(in: rootURL)
        }.value

        var byKey: [String: MediaItem] = [:]
        for item in folder.items { byKey[item.libraryKey] = item }

        var seen = Set<UUID>()
        var newFiles: [(url: URL, relativePath: String)] = []
        var unsupported = 0

        for fileURL in candidates {
            guard EngineRouter.isSupported(fileExtension: fileURL.pathExtension) else {
                unsupported += 1
                continue
            }
            let relative = Self.relativePath(of: fileURL, in: rootURL)

            // Köhnə elementlərdə nisbi yol yoxdur — onları fayl adı ilə tanıyırıq.
            let legacy = byKey[fileURL.lastPathComponent].flatMap { $0.relativePath == nil ? $0 : nil }
            if let item = byKey[relative] ?? legacy, !seen.contains(item.id) {
                if item.relativePath == nil { item.relativePath = relative }
                if item.isMissing || item.bookmark == nil {
                    item.bookmark = Self.bookmark(for: fileURL) ?? item.bookmark
                }
                item.isMissing = false
                seen.insert(item.id)
            } else {
                newFiles.append((fileURL, relative))
            }
        }

        // Qovluq daxilində köçürülmüş fayl: köhnə yerində yoxdur, yeni yerində «yeni»
        // görünür. Ad və ölçü üst-üstə düşürsə eyni fayldır — oxunmuş yer və
        // əlfəcinlər itməsin deyə köhnə element yeni yola bağlanır.
        var unseenBySignature: [String: MediaItem] = [:]
        for item in folder.items where !seen.contains(item.id) {
            unseenBySignature[Self.signature(filename: item.filename, size: item.fileSize)] = item
        }
        if !unseenBySignature.isEmpty {
            newFiles = newFiles.filter { file in
                let key = Self.signature(filename: file.url.lastPathComponent, size: Self.fileSize(of: file.url))
                guard let moved = unseenBySignature.removeValue(forKey: key) else { return true }
                moved.relativePath = file.relativePath
                moved.bookmark = Self.bookmark(for: file.url) ?? moved.bookmark
                moved.isMissing = false
                seen.insert(moved.id)
                return false
            }
        }

        for item in folder.items where !seen.contains(item.id) {
            item.isMissing = true
        }

        progress = Progress(processed: 0, total: newFiles.count, currentFilename: "", unsupported: unsupported)

        for file in newFiles {
            progress.currentFilename = file.url.lastPathComponent
            if let item = await Self.makeItem(from: file.url, relativePath: file.relativePath) {
                item.folder = folder
                context.insert(item)
            }
            progress.processed += 1

            // Hər 50 faylda bir yazırıq ki, böyük kataloqda yaddaş şişməsin.
            if progress.processed % 50 == 0 { try? context.save() }
        }

        folder.lastScannedAt = .now
        progress.isFinished = true
    }

    /// Eyni yola baxan qovluq artıq varmı.
    private func existingFolder(at url: URL) -> LibraryFolder? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let folders = (try? context.fetch(FetchDescriptor<LibraryFolder>())) ?? []
        return folders.first { folder in
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: folder.bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return false }
            return resolved.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
    }

    /// Qovluğu rekursiv gəzir, gizli faylları atır. Disk işidir, MainActor-dan kənarda gedir.
    private nonisolated static func scanFiles(in root: URL) -> [URL] {
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

    /// `/…/Musiqi/Albom/01.mp3` → `Albom/01.mp3`.
    nonisolated static func relativePath(of file: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return file.lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }

    private static func fileSize(of url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
    }

    private static func signature(filename: String, size: Int64) -> String {
        "\(filename.lowercased())|\(size)"
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Bir faylın metadatasını oxuyur. Oxuna bilməsə də element yaradılır —
    /// fayl adı başlıq kimi işlədilir, çünki oxunmayan metadata faylı kitabxanadan
    /// silmək üçün səbəb deyil.
    private static func makeItem(from url: URL, relativePath: String) async -> MediaItem? {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent
        let size = Self.fileSize(of: url)
        let bookmark = Self.bookmark(for: url)

        let probe = await probeMetadata(at: url)

        return MediaItem(
            title: probe.title ?? url.deletingPathExtension().lastPathComponent,
            artist: probe.artist,
            album: probe.album,
            kind: EngineRouter.kind(forFileExtension: ext),
            engine: EngineRouter.engine(forFileExtension: ext),
            filename: filename,
            relativePath: relativePath,
            fileExtension: ext,
            fileSize: size,
            duration: probe.duration,
            bookmark: bookmark,
            artworkData: probe.artwork,
            videoCodec: probe.codec,
            pixelHeight: probe.pixelHeight
        )
    }

    /// Faylın metadatası. Yalnız Sendable dəyərlər saxlayır.
    struct Probe: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double = 0
        var artwork: Data?
        var pixelHeight: Int?
        var codec: String?
    }

    /// AVFoundation tipləri (`AVAsset`, `AVMetadataItem`, `AVAssetTrack`) Sendable deyil,
    /// ona görə onlar bu `nonisolated` funksiyanın içindən çıxmır — bayıra yalnız
    /// `Probe` gedir. Beləliklə metadata oxunması MainActor-u da bloklamır.
    private nonisolated static func probeMetadata(at url: URL) async -> Probe {
        var probe = Probe()
        let asset = AVURLAsset(url: url)

        // AVFoundation MKV oxumur — belə fayllarda bu addım sadəcə boş qayıdır.
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            probe.duration = seconds
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for entry in metadata {
                switch entry.commonKey {
                case .commonKeyTitle:
                    // `try?` + optional dəyər iç-içə optional verir, ona görə düzləşdirilir.
                    if let value = (try? await entry.load(.stringValue)) ?? nil, !value.isEmpty {
                        probe.title = value
                    }
                case .commonKeyArtist:
                    probe.artist = (try? await entry.load(.stringValue)) ?? nil
                case .commonKeyAlbumName:
                    probe.album = (try? await entry.load(.stringValue)) ?? nil
                case .commonKeyArtwork:
                    probe.artwork = (try? await entry.load(.dataValue)) ?? nil
                default:
                    break
                }
            }
        }

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                probe.pixelHeight = Int(abs(size.height))
            }
            if let descriptions = try? await track.load(.formatDescriptions),
               let description = descriptions.first {
                probe.codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
            }
        }

        return probe
    }

    private nonisolated static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
