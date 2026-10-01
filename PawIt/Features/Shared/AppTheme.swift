import SwiftUI
import Core

// MARK: - AppTheme（设计令牌中心——Soft Companion 风格）
//
// 所有屏幕通过此处获取色彩、字体、卡片样式、动画预设，
// 确保视觉一致性。方案 B 核心理念：暖奶油底 + 宠物专属色 + 圆润字体。

enum AppTheme {

    // MARK: - Colors

    /// App 主背景——暖奶油色，替代系统白 `Color(.systemBackground)`
    static let background = Color(red: 1.0, green: 0.973, blue: 0.941)       // #FFF8F0

    /// 卡片/表面背景——比主背景略白
    static let surfaceBackground = Color(red: 1.0, green: 0.988, blue: 0.973) // #FFFCF8

    /// 次级文字——暖灰（非纯灰）
    static let secondaryText = Color(red: 0.557, green: 0.537, blue: 0.514)   // #8E8983

    /// 分割线——极淡暖色
    static let separator = Color(red: 0.933, green: 0.914, blue: 0.886)       // #EEE9E2

    /// 对话气泡背景
    static let bubbleBackground = Color.white.opacity(0.92)

    /// 宠物专属色——基于 PetAsset.accentHue（0-360），转为 SwiftUI Color
    static func petAccentColor(species: PetSpecies) -> Color {
        Color(
            hue: PetAsset.accentHue(species: species) / 360,
            saturation: 0.55,
            brightness: 0.88
        )
    }

    /// 宠物淡色背景（卡片/头部区域）
    static func petTintBackground(species: PetSpecies) -> Color {
        petAccentColor(species: species).opacity(0.12)
    }

    // MARK: - Typography

    /// 大标题——圆润设计（Onboarding 标题、Growth 标题）
    static let largeTitle: Font = .system(.largeTitle, design: .rounded, weight: .bold)

    /// 标题——圆润设计
    static let title: Font = .system(.title2, design: .rounded, weight: .bold)

    /// 副标题——圆润设计
    static let subtitle: Font = .system(.title3, design: .rounded, weight: .semibold)

    /// 卡片标题
    static let cardTitle: Font = .system(.headline, design: .rounded, weight: .semibold)

    /// 正文
    static let body: Font = .system(.body)

    /// 辅助说明——圆润小字
    static let caption: Font = .system(.caption, design: .rounded)

    /// 标签/徽章——小号加粗
    static let badge: Font = .system(.caption2, design: .rounded, weight: .bold)

    // MARK: - Card Styles

    /// 标准圆角
    static let cornerRadius: CGFloat = 16

    /// 小圆角（按钮等）
    static let smallCornerRadius: CGFloat = 12

    /// 卡片阴影
    static let cardShadow: (color: Color, radius: CGFloat, y: CGFloat) = (
        color: Color.black.opacity(0.06),
        radius: 8,
        y: 4
    )

    /// 轻阴影（内部元素）
    static let lightShadow: (color: Color, radius: CGFloat, y: CGFloat) = (
        color: Color.black.opacity(0.04),
        radius: 4,
        y: 2
    )

    // MARK: - Animation Presets

    /// 宠物 idle 轻微浮动
    static let petIdleAnimation: Animation = .easeInOut(duration: 1.8).repeatForever(autoreverses: true)

    /// 宠物开心抖动
    static let petHappyAnimation: Animation = .spring(duration: 0.4, bounce: 0.6)

    /// 卡片出现
    static let cardAppearAnimation: Animation = .spring(duration: 0.5, bounce: 0.3)

    /// 按压反馈
    static let pressAnimation: Animation = .easeInOut(duration: 0.15)

    /// 页面切换
    static let pageTransition: Animation = .spring(duration: 0.6, bounce: 0.2)
}

// MARK: - View Modifiers

extension View {

    /// 暖色 App 背景
    func warmBackground() -> some View {
        self.background(AppTheme.background.ignoresSafeArea())
    }

    /// 卡片样式容器
    func noteCard(preset: NoteStylePreset = .classicYellow) -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(preset.backgroundColor)
                    .shadow(
                        color: AppTheme.cardShadow.color,
                        radius: AppTheme.cardShadow.radius,
                        y: AppTheme.cardShadow.y
                    )
            )
    }

    /// 卡片按压动效
    func pressable() -> some View {
        self.buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Pressable Button Style

/// 轻微缩放的按钮反馈——让卡片点击有"软糯"手感
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppTheme.pressAnimation, value: configuration.isPressed)
    }
}
