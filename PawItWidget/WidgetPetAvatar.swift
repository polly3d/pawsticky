import SwiftUI
import Core

/// Widget 内宠物渲染（W6-2 → W7 升级）——优先使用真实美术资产。
struct WidgetPetAvatar: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat
    var pose: PetPose = .holding

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.2,
                        brightness: 0.97
                    )
                )
                .frame(width: size, height: size)

            petImage
                .frame(width: size * 0.85, height: size * 0.85)

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

    @ViewBuilder
    private var petImage: some View {
        let poseName = PetAsset.imageName(species: species, pose: pose)
        let frontName = "pet-\(species.rawValue)-front"

        if UIImage(named: poseName) != nil {
            Image(poseName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if UIImage(named: frontName) != nil {
            Image(frontName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: PetAsset.placeholderSymbol(species: species))
                .font(.system(size: size * 0.45))
                .foregroundStyle(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.6,
                        brightness: 0.45
                    )
                )
        }
    }
}
