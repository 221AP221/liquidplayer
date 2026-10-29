import Foundation
import SwiftData

/// İstifadəçinin faylda işarələdiyi an. Fayl itəndə də silinmir —
/// qovluq qayıdanda əlfəcinlər yerində olur.
@Model
final class Bookmark {
    @Attribute(.unique) var id: UUID

    /// Saniyə ilə mövqe.
    var position: Double
    /// Boşdursa UI fəsil adını və ya vaxtı göstərir.
    var note: String
    var createdAt: Date

    @Relationship(inverse: \MediaItem.bookmarks) var item: MediaItem?

    init(id: UUID = UUID(), position: Double, note: String = "", item: MediaItem? = nil) {
        self.id = id
        self.position = position
        self.note = note
        self.createdAt = .now
        self.item = item
    }
}
