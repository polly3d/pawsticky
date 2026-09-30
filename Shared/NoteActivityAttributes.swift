import ActivityKit
import Foundation

/// 便签 Live Activity 的数据模型——钉便签到锁屏的核心。
///
/// 同时编译于 PawIt App 和 PawItWidget 两个 target（via Shared/ 目录）。
/// - App 调 `Activity.request(attributes:content:)` 启动
/// - Widget Extension 用 `ActivityConfiguration(for:)` 渲染
struct NoteActivityAttributes: ActivityAttributes {

    // MARK: - 静态属性（启动时设定，生命周期内不变）

    /// 便签 ID（UUID 字符串），用于 App 更新/结束时匹配。
    let noteId: String
    /// 宠物物种 rawValue（直接映射 Asset Catalog 图片名）。
    let petSpecies: String
    /// 宠物显示名（如 "Biscuit"）。
    let petName: String

    // MARK: - 动态内容（可通过 Activity.update 实时刷新）

    struct ContentState: Codable, Hashable {
        /// 便签正文。
        let noteText: String
        /// 清单项快照。
        let items: [ChecklistItem]
        /// 颜色预设 rawValue（nil = classicYellow）。
        let noteStyle: String?
        /// 便签是否已完成。
        let isDone: Bool
    }

    /// 清单项快照（Codable 值类型，无数据库依赖）。
    struct ChecklistItem: Codable, Hashable {
        let text: String
        let done: Bool
    }
}
