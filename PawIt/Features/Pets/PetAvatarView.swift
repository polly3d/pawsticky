import SwiftUI
import Core

/// 宠物渲染器（Soft Companion 升级）——温暖光晕 + idle 浮动动画。
///
/// 所有 6 种宠物都有 `pet-{species}-front` 正面图（从角色卡裁出）。
/// cat/corgi 额外有 `pet-{species}-holding` 和 `pet-{species}-happy` 姿势图。
///
/// `animated: true` 时启用 idle 轻微浮动，让宠物"活"起来。
struct PetAvatarView: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat
    var pose: PetPose = .holding
    var animated: Bool = false

    @State private var idleOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // 背景光晕——暖色调升级
            Circle()
                .fill(
                    AppTheme.petTintBackground(species: species)
                )
                .frame(width: size, height: size)

            // 宠物图
            Image("pet-\(species.rawValue)-front")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
                .offset(y: idleOffset)

            // 心情指示
            if mood == .happy {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.18))
                    .foregroundStyle(.pink)
                    .offset(x: size * 0.3, y: -size * 0.3 + idleOffset)
            } else if mood == .worried {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(.orange)
                    .offset(x: size * 0.3, y: -size * 0.3 + idleOffset)
            }
        }
        .onAppear {
            if animated {
                withAnimation(AppTheme.petIdleAnimation) {
                    idleOffset = -4
                }
            }
        }
    }
}
