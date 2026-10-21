import Foundation

/// PawIt 跨 target 共享的常量与基础模型(纯逻辑层,无 UI 依赖)。
/// 模型类型按计划 §1.1 一文件一职责,位于 `Models/`(Note/NoteItem/PetProfile/GrowthState)。

public enum PawItInfo {
    /// 三 target(App / Widget / Watch)共享的 App Group 标识。
    public static let appGroupID = "group.com.fitpetgo.pawsticky.shared"

    /// 隐私政策页。审核指南 5.1.1(i) 要求 App 内可达，同一个 URL 也要填进 App Store Connect。
    ///
    /// 2026-10-21 拍板：直接用 fitpetgo.com 的网站通用政策，不另发 PawSticky 专属页（决议见 docs/launch-todo.md D2）。
    /// 已知风险：该页写明“不适用于其他渠道”、没提 App，5.1.1(i) 有拒审可能；
    /// 若被拒，发布备用稿 docs/pawsticky-privacy-policy.md 并改本常量即可。
    public static let privacyPolicyURL = URL(string: "https://www.fitpetgo.com/privacy-policy")!

    /// 支持页（ASC 的 Support URL 也填它）。
    public static let supportURL = URL(string: "https://www.fitpetgo.com/contact-us")!
}
