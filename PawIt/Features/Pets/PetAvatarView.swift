import SwiftUI
import Core

/// 宠物占位渲染器（W6-5）——SF Symbol 占位图，真实 PNG 就绪后替换。
///
/// Widget 和 App 内均可使用。根据 PetNoteRenderer 的布局参数定位宠物图。
struct PetAvatarView: View {
    let species: PetSpecies
    let mood: PetMood
    let size: CGFloat

    var body: some View {
        ZStack {
            // 背景光晕
            Circle()
                .fill(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.3,
                        brightness: 0.95
                    )
                )
                .frame(width: size, height: size)

            // 宠物图标
            Image(systemName: PetAsset.placeholderSymbol(species: species))
                .font(.system(size: size * 0.45))
                .foregroundStyle(
                    Color(
                        hue: PetAsset.accentHue(species: species) / 360,
                        saturation: 0.6,
                        brightness: 0.45
                    )
                )

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
