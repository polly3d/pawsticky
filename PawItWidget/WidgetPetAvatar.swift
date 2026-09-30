import SwiftUI
import Core

/// Widget 内宠物渲染（W6-2 → W7 升级）——优先使用真实美术资产。
///
/// Widget 中不使用 UIImage(named:) 检查（扩展进程的 Bundle.main 行为不同），
/// 直接按 species 加载已知的 Asset Catalog 图片。
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

            // 直接加载 front 图（所有 6 种宠物都有）
            Image("pet-\(species.rawValue)-front")
                .resizable()
                .aspectRatio(contentMode: .fit)
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
}
