import Foundation

/// Player-in bir anlıq vəziyyəti. UI yalnız bunu oxuyur.
struct PlaybackSnapshot: Equatable, Sendable {
    var isPlaying: Bool = false
    var position: Double = 0        // saniyə
    var duration: Double = 0        // saniyə
    var isBuffering: Bool = false
    var engine: EngineKind = .system

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

enum RepeatMode: Int, CaseIterable, Sendable {
    case off, all, one
}

/// Oxutma zamanı istifadəçiyə bir dəfə göstərilən xəbərdarlıqlar.
enum PlaybackNotice: Equatable, Sendable {
    /// VLC mühərriki işə düşür: PiP və AirPlay video itir.
    case softwareDecoding(codec: String?)
    case fileMissing(filename: String)
    case unsupportedFormat(fileExtension: String)
    case corruptedAt(seconds: Double)
}

enum PlaybackError: Error, Equatable, Sendable {
    case bookmarkUnresolvable
    case accessDenied
    case unsupported(String)
    case engineFailed(String)
}
