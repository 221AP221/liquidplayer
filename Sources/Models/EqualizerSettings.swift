import Foundation

/// 10 zolaqlı ekvalayzer. Hər iki mühərrik eyni dəyərləri alır:
/// AVFoundation-da `AudioEqualizerTap` biquad filtrləri ilə, VLC-də öz EQ-su ilə.
struct EqualizerSettings: Codable, Equatable, Sendable {

    /// Zolaqların mərkəz tezlikləri (Hz). VLC-nin öz zolaqları bir az fərqlidir
    /// (60 Hz ... 16 kHz), ora indeks üzrə ötürülür — qulaq fərqi hiss etmir.
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    /// Hər zolağın maksimum gücləndirmə/zəiflətməsi (dB).
    static let gainRange: ClosedRange<Float> = -12...12

    var isEnabled: Bool
    /// dB ilə, `frequencies` ilə eyni uzunluqda.
    var gains: [Float]
    var preset: EqualizerPreset?

    static let flat = EqualizerSettings(isEnabled: false, gains: EqualizerPreset.flat.gains, preset: .flat)

    /// Bütün zolaqlar 0-dırsa filtr heç nə dəyişmir — tap keçid rejiminə düşür.
    var isEffectivelyFlat: Bool { !isEnabled || gains.allSatisfy { abs($0) < 0.05 } }

    mutating func setGain(_ gain: Float, at index: Int) {
        guard gains.indices.contains(index) else { return }
        gains[index] = min(Self.gainRange.upperBound, max(Self.gainRange.lowerBound, gain))
        preset = nil
    }

    mutating func apply(_ preset: EqualizerPreset) {
        gains = preset.gains
        self.preset = preset
    }

    /// Köhnə və ya zədəli saxlanmış dəyərlər zolaq sayına uyğunlaşdırılır.
    func normalized() -> EqualizerSettings {
        var copy = self
        let count = Self.frequencies.count
        if copy.gains.count != count {
            copy.gains = Array((copy.gains + Array(repeating: 0, count: count)).prefix(count))
        }
        return copy
    }
}

enum EqualizerPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat, bassBoost, trebleBoost, vocal, spokenWord, loudness

    var id: String { rawValue }

    var titleKey: String { "eq.preset.\(rawValue)" }

    var gains: [Float] {
        switch self {
        case .flat:        [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:   [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .vocal:       [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]
        // Səsli kitablar üçün: aşağı uğultu kəsilir, nitq aydınlaşır.
        case .spokenWord:  [-6, -4, -2, 0, 2, 4, 4, 2, 0, -2]
        case .loudness:    [5, 4, 1, 0, -1, 0, 0, 1, 4, 5]
        }
    }
}
