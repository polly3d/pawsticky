import Foundation

/// PawIt 跨 target 共享的常量与基础模型(纯逻辑层,无 UI 依赖)。
/// 模型类型按计划 §1.1 一文件一职责,位于 `Models/`(Note/NoteItem/PetProfile/GrowthState)。

public enum PawItInfo {
    /// 三 target(App / Widget / Watch)共享的 App Group 标识。
    public static let appGroupID = "group.com.fitpetgo.pawsticky.shared"
}
