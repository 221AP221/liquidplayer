import Foundation
import SwiftData

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case audio
    case video
    case audiobook
}

/// Faylı hansı mühərrikin oxuyacağı. İdxal zamanı təyin olunur, oxutma zamanı
/// dəqiqləşdirilə bilər (məsələn aparat dekoderi treki rədd edərsə).
enum EngineKind: String, Codable, Sendable {
    /// AVFoundation — aparat dekoderi, PiP və AirPlay tam işləyir.
    case system
    /// VLCKit — proqram dekodlaşdırma; MKV, FLAC, ekzotik kodeklər.
    case vlc
}

@Model
final class MediaItem {
    /// Sabit kimlik. Fayl yerini dəyişəndə də eyni qalır.
    @Attribute(.unique) var id: UUID

    var title: String
    var artist: String?
    var album: String?
    var kindRaw: String
    var engineRaw: String

    /// Faylın adı — üz qabığı yoxdursa rəng bundan qurulur.
    var filename: String
    var fileExtension: String
    var fileSize: Int64
    var duration: Double

    /// Faylı yenidən açmaq üçün security-scoped bookmark.
    /// Qovluq icazəsi itəndə bu boşalmır — sadəcə həll olunmur.
    @Attribute(.externalStorage) var bookmark: Data?

    @Attribute(.externalStorage) var artworkData: Data?

    var addedAt: Date
    var lastPlayedAt: Date?
    /// 0...1. 0.98-dən yuxarı "baxılıb" sayılır.
    var progress: Double
    var isFavorite: Bool

    /// Video üçün: eni/hündürlüyü, kodek adı — UI-da rozetlərdə göstərilir.
    var videoCodec: String?
    var pixelHeight: Int?

    /// Fayl son yoxlamada yerində idimi.
    var isMissing: Bool

    @Relationship(inverse: \LibraryFolder.items) var folder: LibraryFolder?

    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        album: String? = nil,
        kind: MediaKind,
        engine: EngineKind,
        filename: String,
        fileExtension: String,
        fileSize: Int64 = 0,
        duration: Double = 0,
        bookmark: Data? = nil,
        artworkData: Data? = nil,
        videoCodec: String? = nil,
        pixelHeight: Int? = nil,
        folder: LibraryFolder? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.kindRaw = kind.rawValue
        self.engineRaw = engine.rawValue
        self.filename = filename
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.duration = duration
        self.bookmark = bookmark
        self.artworkData = artworkData
        self.videoCodec = videoCodec
        self.pixelHeight = pixelHeight
        self.addedAt = .now
        self.lastPlayedAt = nil
        self.progress = 0
        self.isFavorite = false
        self.isMissing = false
        self.folder = folder
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    var engine: EngineKind {
        get { EngineKind(rawValue: engineRaw) ?? .system }
        set { engineRaw = newValue.rawValue }
    }

    var isVideo: Bool { kind == .video }

    /// Qaldığı yerdən davam etməyə dəyərmi.
    var isResumable: Bool { progress > 0.02 && progress < 0.98 }

    var remainingSeconds: Double { max(0, duration * (1 - progress)) }
}
