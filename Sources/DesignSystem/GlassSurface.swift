import SwiftUI

/// Layihənin şüşə materialı. iOS 18-də `.glassEffect` hələ yoxdur, ona görə
/// material + kənar + yuxarı parıltı əl ilə qurulur; iOS 26-ya keçəndə yalnız
/// bu fayl dəyişəcək, çağıran ekranlar yox.
struct GlassBackground: View {
    var cornerRadius: CGFloat = Theme.Radius.card
    var tint: Color = Theme.Colors.glassFill
    var elevated: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(tint))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.Colors.glassSheen, Theme.Colors.glassStroke],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(elevated ? 0.5 : 0.28),
                radius: elevated ? 34 : 18,
                y: elevated ? 18 : 10
            )
    }
}

extension View {
    /// Kart, sheet və panellər üçün.
    func glassCard(
        cornerRadius: CGFloat = Theme.Radius.card,
        elevated: Bool = false
    ) -> some View {
        background(GlassBackground(cornerRadius: cornerRadius, elevated: elevated))
    }

    /// Dairəvi düymələr üçün.
    func glassCircle(diameter: CGFloat) -> some View {
        frame(width: diameter, height: diameter)
            .background(GlassBackground(cornerRadius: diameter / 2))
            .contentShape(Circle())
    }

    /// Hər toxunulan elementin minimum sahəsi.
    func hitTarget(_ size: CGFloat = Theme.Size.hitTarget) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

/// Siyahılarda istifadə olunan nazik ayırıcı.
struct RowSeparator: View {
    var inset: CGFloat = 56

    var body: some View {
        Theme.Colors.separator
            .frame(height: 1)
            .padding(.leading, inset)
    }
}
