import SwiftUI

/// Üz qabığı. Şəkil yoxdursa faylın adından sabit qradiyent qurulur —
/// beləliklə eyni fayl həmişə eyni rəngdə görünür.
struct ArtworkView: View {
    var image: UIImage?
    var seed: String
    var cornerRadius: CGFloat = Theme.Radius.row
    var isVideo: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(gradient)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else if isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    /// Ad → sabit rəng cütü.
    private var gradient: LinearGradient {
        let palette = ArtworkPalette.forSeed(seed)
        return LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum ArtworkPalette {
    private static let sets: [[Color]] = [
        [Color(red: 1.00, green: 0.541, blue: 0.361), Color(red: 0.298, green: 0.180, blue: 0.541)],
        [Color(red: 0.184, green: 0.714, blue: 0.769), Color(red: 0.082, green: 0.133, blue: 0.290)],
        [Color(red: 0.910, green: 0.765, blue: 0.416), Color(red: 0.294, green: 0.141, blue: 0.094)],
        [Color(red: 0.557, green: 0.482, blue: 1.00),  Color(red: 0.114, green: 0.102, blue: 0.235)],
        [Color(red: 1.00, green: 0.478, blue: 0.612),  Color(red: 0.169, green: 0.067, blue: 0.251)],
        [Color(red: 0.498, green: 0.847, blue: 0.627), Color(red: 0.078, green: 0.188, blue: 0.122)]
    ]

    static func forSeed(_ seed: String) -> [Color] {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return sets[Int(hash % UInt64(sets.count))]
    }

    /// Now Playing fonunda istifadə olunan üç ləkə.
    static func glowColors(for seed: String) -> [Color] {
        let base = forSeed(seed)
        return [base[0], base[1], base[0].opacity(0.7)]
    }
}

/// Kitabxana / player başlıqlarının üstündəki kiçik yazı.
struct SectionHeader: View {
    var title: LocalizedStringKey

    var body: some View {
        SwiftUI.Text(title)
            .font(Theme.Text.overline)
            .textCase(.uppercase)
            .kerning(0.4)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

/// Segmentli seçici (Hamısı / Audio / Video).
struct GlassSegmentedControl<Item: Hashable>: View {
    var items: [Item]
    var label: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(items, id: \.self) { item in
                let isOn = item == selection
                Button {
                    withAnimation(Theme.Motion.snap) { selection = item }
                } label: {
                    SwiftUI.Text(label(item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 18)
    }
}
