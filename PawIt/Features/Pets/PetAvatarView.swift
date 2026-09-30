import SwiftUI
import Core

/// 宠物渲染器（W7 升级）——优先使用真实美术资产。
///
/// 所有 6 种宠物都有 `pet-{species}-front` 正面图（从角色卡裁出）。
/// cat/corgi 额外有 `pet-{species}-holding` 和 `pet-{species}-happy` 姿势图。
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

            // 宠物图：直接加载 front 图（全部 6 种宠物都有）
            Image("pet-\(species.rawValue)-front")
                .resizable()
                .aspectRatio(contentMode: .fit)
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
}
