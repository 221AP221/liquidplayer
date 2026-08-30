import SwiftUI

/// Bütün rəng, ölçü və tipoqrafiya dəyərləri burada. Ekranlarda sabit ədəd yazılmır.
enum Theme {

    // MARK: - Rənglər

    enum Colors {
        /// Ən alt fon. Şüşə səthlər bunun üstündə yerləşir.
        static let base = Color(red: 0.027, green: 0.027, blue: 0.043)

        static let textPrimary   = Color(red: 0.949, green: 0.949, blue: 0.961)
        static let textSecondary = Color.white.opacity(0.58)
        static let textTertiary  = Color.white.opacity(0.38)

        /// Standart vurğu. `AppSettings.accent` bunu əvəz edə bilər.
        static let accent  = Color(red: 1.0,   green: 0.698, blue: 0.361)
        static let violet  = Color(red: 0.494, green: 0.424, blue: 1.0)
        static let teal    = Color(red: 0.227, green: 0.769, blue: 0.769)
        static let rose    = Color(red: 1.0,   green: 0.608, blue: 0.706)
        static let gold    = Color(red: 0.910, green: 0.765, blue: 0.416)
        static let mint    = Color(red: 0.498, green: 0.847, blue: 0.627)

        /// Şüşə səthin daxili dolğusu və kənarı.
        static let glassFill   = Color.white.opacity(0.07)
        static let glassStroke = Color.white.opacity(0.11)
        static let glassSheen  = Color.white.opacity(0.18)
        static let separator   = Color.white.opacity(0.07)
    }

    // MARK: - Ölçülər

    enum Radius {
        static let card: CGFloat    = 22
        static let control: CGFloat = 16
        static let row: CGFloat     = 11
        static let sheet: CGFloat   = 30
        static let pill: CGFloat    = 999
    }

    enum Spacing {
        static let hairline: CGFloat = 2
        static let xs: CGFloat  = 6
        static let sm: CGFloat  = 10
        static let md: CGFloat  = 14
        static let lg: CGFloat  = 20
        static let xl: CGFloat  = 26
        static let xxl: CGFloat = 34

        /// Ekranların sol/sağ standart kənarı.
        static let screenEdge: CGFloat = 20
    }

    enum Size {
        /// HIG minimumu. Heç bir toxunulan element bundan kiçik olmur.
        static let hitTarget: CGFloat   = 44
        static let miniPlayer: CGFloat  = 62
        static let tabBar: CGFloat      = 56
        static let artThumb: CGFloat    = 44
        static let transportMain: CGFloat = 76
    }

    // MARK: - Tipoqrafiya

    enum Text {
        static let largeTitle = Font.system(size: 32, weight: .bold).width(.standard)
        static let title      = Font.system(size: 23, weight: .bold)
        static let headline   = Font.system(size: 17, weight: .semibold)
        static let body       = Font.system(size: 15, weight: .regular)
        static let rowTitle   = Font.system(size: 15, weight: .medium)
        static let caption    = Font.system(size: 12.5, weight: .regular)
        static let overline   = Font.system(size: 13, weight: .semibold)
        static let numeric    = Font.system(size: 12, weight: .regular).monospacedDigit()
    }

    enum Motion {
        static let snap = Animation.spring(response: 0.34, dampingFraction: 0.86)
        static let ease = Animation.easeOut(duration: 0.22)
    }
}

// MARK: - Üz qabığından çıxarılan fon

/// Now Playing arxasındakı yumşaq işıq. Üz qabığı olmayanda vurğu rəngindən qurulur.
struct ArtworkGlow: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            Theme.Colors.base
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Ellipse()
                    .fill(color.opacity(0.5))
                    .frame(width: 460, height: 420)
                    .offset(
                        x: index == 0 ? -110 : (index == 1 ? 130 : 10),
                        y: index == 0 ? -230 : (index == 1 ? -40 : 300)
                    )
                    .blur(radius: 70)
            }
            LinearGradient(
                colors: [Theme.Colors.base.opacity(0.28), Theme.Colors.base.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
