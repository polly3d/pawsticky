import Foundation

// MARK: - PetNoteRenderer（W6-1）
//
// 宠物举牌布局引擎：纯值函数，给定 (species, pose, widgetFamily 尺寸类别)
// 输出布局参数。View 层消费布局值渲染，Engine 不依赖 SwiftUI。
//
// 设计决策：
// - 三种 Widget 尺寸各有不同的宠物/便签比例和位置
// - 宠物图始终在便签旁边或后面（举牌效果）
// - 布局参数用 CGFloat 比例值，View 层按实际尺寸缩放

/// 宠物举牌布局参数（Engine 输出，View 层消费）。
public struct PetNoteLayout: Equatable, Sendable {
    /// 宠物图占总宽度的比例。
    public let petWidthRatio: CGFloat
    /// 宠物图相对于容器底部的偏移比例（0 = 底部对齐）。
    public let petBottomOffset: CGFloat
    /// 宠物图水平位置（0 = 左对齐，1 = 右对齐）。
    public let petHorizontalAlignment: CGFloat
    /// 便签卡片占总宽度的比例。
    public let noteWidthRatio: CGFloat
    /// 便签卡片占总高度的比例。
    public let noteHeightRatio: CGFloat
    /// 便签卡片相对于容器的水平偏移比例。
    public let noteHorizontalOffset: CGFloat
    /// 便签卡片相对于容器的垂直偏移比例。
    public let noteVerticalOffset: CGFloat
}

/// 宠物举牌布局引擎（全部纯函数，零 SwiftUI 依赖）。
public enum PetNoteRenderer {

    /// Widget 尺寸类别（抽象化 WidgetFamily，Engine 不依赖 WidgetKit）。
    public enum SizeClass: Equatable, Sendable {
        case small
        case medium
        case large
    }

    /// 计算宠物举牌布局。
    ///
    /// - Parameters:
    ///   - pose: 宠物姿势（holding = 举牌在前，sitting = 宠物在侧）
    ///   - sizeClass: Widget 尺寸类别
    /// - Returns: 布局参数
    public static func layout(pose: PetPose, sizeClass: SizeClass) -> PetNoteLayout {
        switch (pose, sizeClass) {
        // Small：宠物在右下角小图，便签占主区域
        case (.holding, .small):
            return PetNoteLayout(
                petWidthRatio: 0.35,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 1.0,
                noteWidthRatio: 0.95,
                noteHeightRatio: 0.65,
                noteHorizontalOffset: 0.0,
                noteVerticalOffset: 0.0
            )
        case (.sitting, .small), (.sleeping, .small):
            return PetNoteLayout(
                petWidthRatio: 0.30,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 1.0,
                noteWidthRatio: 0.95,
                noteHeightRatio: 0.70,
                noteHorizontalOffset: 0.0,
                noteVerticalOffset: 0.0
            )
        case (.happy, .small):
            return PetNoteLayout(
                petWidthRatio: 0.40,
                petBottomOffset: 0.05,
                petHorizontalAlignment: 1.0,
                noteWidthRatio: 0.90,
                noteHeightRatio: 0.60,
                noteHorizontalOffset: 0.0,
                noteVerticalOffset: 0.0
            )

        // Medium：宠物在左侧，便签在右侧
        case (.holding, .medium):
            return PetNoteLayout(
                petWidthRatio: 0.30,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 0.0,
                noteWidthRatio: 0.65,
                noteHeightRatio: 0.90,
                noteHorizontalOffset: 0.32,
                noteVerticalOffset: 0.05
            )
        case (_, .medium):
            return PetNoteLayout(
                petWidthRatio: 0.25,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 0.0,
                noteWidthRatio: 0.70,
                noteHeightRatio: 0.90,
                noteHorizontalOffset: 0.28,
                noteVerticalOffset: 0.05
            )

        // Large：宠物在左下角，便签占大部分面积
        case (.holding, .large):
            return PetNoteLayout(
                petWidthRatio: 0.25,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 0.0,
                noteWidthRatio: 0.95,
                noteHeightRatio: 0.80,
                noteHorizontalOffset: 0.0,
                noteVerticalOffset: 0.0
            )
        case (_, .large):
            return PetNoteLayout(
                petWidthRatio: 0.20,
                petBottomOffset: 0.0,
                petHorizontalAlignment: 0.0,
                noteWidthRatio: 0.95,
                noteHeightRatio: 0.85,
                noteHorizontalOffset: 0.0,
                noteVerticalOffset: 0.0
            )
        }
    }

    /// 根据便签状态推导宠物姿势。
    public static func inferPose(isDone: Bool, isOverdue: Bool, hasNotes: Bool) -> PetPose {
        if !hasNotes { return .sleeping }
        if isDone { return .happy }
        if isOverdue { return .holding }
        return .holding
    }

    /// 根据便签状态推导宠物心情。
    public static func inferMood(isDone: Bool, isOverdue: Bool) -> PetMood {
        if isDone { return .happy }
        if isOverdue { return .worried }
        return .neutral
    }
}
