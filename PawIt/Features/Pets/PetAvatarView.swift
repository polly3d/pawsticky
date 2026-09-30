import SwiftUI
import Core

/// 宠物渲染器（W6-5 → W7 升级）——优先使用真实美术资产，降级到 SF Symbol。
///
/// 资产查找顺序：
/// 1. pose 精确图：`pet-{species}-{pose}`（如 pet-cat-holding）
/// 2. 正面通用图：`pet-{species}-front`（角色卡正面裁剪）
/// 3. SF Symbol 占位（最终降级）
struct PetAvatarView: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat
    var pose: PetPose = .holding

    var body: some View {
        ZStack {
            // 背景光晕
            Circle()
                .fill(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.2,
                        brightness: 0.97
                    )
                )
                .frame(width: size, height: size)

            // 宠物图（真实资产 → 降级 SF Symbol）
            petImage
                .frame(width: size * 0.85, height: size * 0.85)

            // 心情指示（仅 happy/worried 时显示小图标）
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

    /// 尝试加载真实图片，降级到 SF Symbol。
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
