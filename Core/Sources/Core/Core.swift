import Foundation

/// PawIt 跨 target 共享的常量与基础模型(纯逻辑层,无 UI 依赖)。
/// 模型类型按计划 §1.1 一文件一职责,位于 `Models/`(Note/NoteItem/PetProfile/GrowthState)。

public enum PawItInfo {
    /// 三 target(App / Widget / Watch)共享的 App Group 标识。
    public static let appGroupID = "group.com.fitpetgo.pawsticky.shared"

    /// 隐私政策页。审核指南 5.1.1(i) 要求 App 内可达，同一个 URL 也要填进 App Store Connect。
    ///
    /// ⚠️ 目前指向 fitpetgo.com 的**网站**通用政策，它写明“不适用于其他渠道”、没提 App，
    /// 提审前必须换成 PawSticky 专属页（稿子见 docs/pawsticky-privacy-policy.md，待办见 docs/launch-todo.md D2）。
    /// 换掉之后 `scripts/preflight.sh` 里对应的 ⏳ 项会自动消失。
    public static let privacyPolicyURL = URL(string: "https://www.fitpetgo.com/privacy-policy")!

    /// 支持页（ASC 的 Support URL 也填它）。
    public static let supportURL = URL(string: "https://www.fitpetgo.com/contact-us")!
}
