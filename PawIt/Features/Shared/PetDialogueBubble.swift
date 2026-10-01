import SwiftUI

/// 宠物对话气泡——Soft Companion 风格的核心 UI 组件。
///
/// 用于 Onboarding 欢迎语、选宠后的反馈语、空列表引导等场景。
/// 气泡下方有三角指向箭头，指向说话的宠物。
struct PetDialogueBubble: View {
    let text: String
    var maxWidth: CGFloat = 280
    /// 箭头偏移：0 = 居中，正值 = 右偏，负值 = 左偏
    var arrowOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(AppTheme.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: maxWidth)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                        .fill(AppTheme.bubbleBackground)
                        .shadow(
                            color: AppTheme.lightShadow.color,
                            radius: AppTheme.lightShadow.radius,
                            y: AppTheme.lightShadow.y
                        )
                )

            // 三角箭头
            Triangle()
                .fill(AppTheme.bubbleBackground)
                .frame(width: 16, height: 10)
                .offset(x: arrowOffset)
                .shadow(
                    color: AppTheme.lightShadow.color,
                    radius: 2,
                    y: 2
                )
        }
    }
}

/// 三角形 Shape（气泡箭头用）
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}
