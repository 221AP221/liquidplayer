import Foundation
import SwiftData

/// Ekranların istifadə etdiyi hazır sorğular. `@Query` predikatları bir yerdə
/// dursun ki, ekranlarda SwiftData detalı görünməsin.
enum LibraryQueries {

    static func items(kind: MediaKind?) -> FetchDescriptor<MediaItem> {
        var descriptor: FetchDescriptor<MediaItem>
        if let kind {
            let raw = kind.rawValue
            descriptor = FetchDescriptor(predicate: #Predicate { $0.kindRaw == raw && !$0.isMissing })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { !$0.isMissing })
        }
        descriptor.sortBy = [SortDescriptor(\.addedAt, order: .reverse)]
        return descriptor
    }

    /// «Davam et» sətri: başlanmış, amma bitməmiş fayllar.
    static var resumable: FetchDescriptor<MediaItem> {
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.progress > 0.02 && $0.progress < 0.98 && !$0.isMissing }
        )
        descriptor.sortBy = [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        descriptor.fetchLimit = 12
        return descriptor
    }

    /// Qeyd: SwiftData predikatları `localizedStandardContains` dəstəkləmir,
    /// ona görə axtarış yaddaşda filtrlənir (`SearchScreen`). Kitabxana 10 000
    /// faylı keçəndə burada FTS5 indeksinə keçmək lazım gələcək.
}

extension Double {
    /// 254 → "4:14", 4820 → "1:20:20"
    var timeLabel: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
