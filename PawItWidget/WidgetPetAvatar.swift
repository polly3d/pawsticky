import SwiftUI
import Core

/// Widget 内宠物占位渲染（W6-2）——轻量版，不含动画。
struct WidgetPetAvatar: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.3,
                        brightness: 0.95
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: PetAsset.placeholderSymbol(species: species))
                .font(.system(size: size * 0.45))
                .foregroundStyle(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.6,
                        brightness: 0.45
                    )
                )

            if mood == .happy {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.18))
                    .foregroundStyle(.pink)
                    .offset(x: size * 0.3, y: -size * 0.3)
            } else if mood == .worried {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(.orange)
                    .offset(x: size * 0.3, y: -size * 0.3)
            }
        }
    }
}
