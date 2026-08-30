import Foundation
import SwiftData

/// İstifadəçinin Files-dan seçdiyi qovluq. Fayllar köçürülmür —
/// yalnız security-scoped bookmark saxlanılır.
@Model
final class LibraryFolder {
    @Attribute(.unique) var id: UUID
    var displayName: String
    @Attribute(.externalStorage) var bookmark: Data

    var addedAt: Date
    var lastScannedAt: Date?

    /// İcazə itibsə UI qovluğu qırmızı işarələyir, faylları gizlədir,
    /// amma oxunmuş yerləri və playlistləri saxlayır.
    var hasAccess: Bool

    @Relationship(deleteRule: .cascade) var items: [MediaItem]

    init(id: UUID = UUID(), displayName: String, bookmark: Data) {
        self.id = id
        self.displayName = displayName
        self.bookmark = bookmark
        self.addedAt = .now
        self.lastScannedAt = nil
        self.hasAccess = true
        self.items = []
    }
}
