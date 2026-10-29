import SwiftUI

/// 10 zolaqlı ekvalayzer. Dəyişiklik dərhal səslənir və bütün fayllar üçün saxlanılır.
struct EqualizerSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var player = player

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Toggle("eq.enabled", isOn: $player.equalizer.isEnabled)
                        .font(Theme.Text.headline)
                        .tint(Theme.Colors.accent)
                        .padding(Theme.Spacing.md)
                        .glassCard(cornerRadius: Theme.Radius.control)

                    presets
                    bands
                        .opacity(player.equalizer.isEnabled ? 1 : 0.4)
                        .disabled(!player.equalizer.isEnabled)

                    if !player.supportsEqualizer {
                        Label("eq.unsupported", systemImage: "exclamationmark.triangle")
                            .font(Theme.Text.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Text("eq.hint")
                        .font(Theme.Text.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.base)
            .navigationTitle("eq.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("eq.reset") {
                        player.equalizer.apply(.flat)
                    }
                    .disabled(player.equalizer.gains == EqualizerPreset.flat.gains)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Hissələr

    private var presets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(EqualizerPreset.allCases) { preset in
                    let isOn = player.equalizer.preset == preset
                    Button {
                        withAnimation(Theme.Motion.snap) {
                            player.equalizer.apply(preset)
                            player.equalizer.isEnabled = true
                        }
                    } label: {
                        Text(LocalizedStringKey(preset.titleKey))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(minHeight: 36)
                            .background {
                                if isOn {
                                    Capsule().fill(Theme.Colors.accent)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.10))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var bands: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(EqualizerSettings.frequencies.enumerated()), id: \.offset) { index, frequency in
                VStack(spacing: Theme.Spacing.xs) {
                    Text(gainLabel(player.equalizer.gains[index]))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VerticalGainSlider(
                        value: Binding(
                            get: { player.equalizer.gains[index] },
                            set: { player.equalizer.setGain($0, at: index) }
                        ),
                        range: EqualizerSettings.gainRange
                    )
                    .frame(height: 180)
                    .accessibilityLabel(Text(frequencyLabel(frequency)))

                    Text(frequencyLabel(frequency))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.xs)
        .glassCard(cornerRadius: Theme.Radius.card)
    }

    private func frequencyLabel(_ frequency: Float) -> String {
        frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
    }

    private func gainLabel(_ gain: Float) -> String {
        let rounded = Int(gain.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

/// Şaquli sürüşdürücü. SwiftUI `Slider`-i fırlatmaq layoutu pozur,
/// ona görə zolaq əl ilə çəkilir. Dolğu sıfırdan (ortadan) başlayır.
struct VerticalGainSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float>
    var step: Float = 0.5

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((value - range.lowerBound) / span)
            let zeroFraction = CGFloat((0 - range.lowerBound) / span)
            let knobY = height * (1 - fraction)
            let zeroY = height * (1 - zeroFraction)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 4)

                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: 4, height: abs(knobY - zeroY))
                    .offset(y: min(knobY, zeroY))

                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(y: knobY - 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clamped = min(max(drag.location.y, 0), height)
                        let raw = range.lowerBound + Float(1 - clamped / height) * span
                        value = (raw / step).rounded() * step
                    }
            )
        }
        .accessibilityElement()
        .accessibilityValue(Text(String(format: "%+.1f dB", value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }
}
