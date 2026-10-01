import Foundation

/// Onboarding 门面（方案 A 极简三步）——首启判定 + widget 引导一次性标记。
///
/// 首启判定是**数据驱动**的（无选中宠物 && 便签数为 0），不设独立
/// 「已完成引导」标记：宠物一经选择即永不再触发（宠物不可删除），
/// 用户中途强退则落在正常空状态——零状态可漂移、零迁移成本。
/// 竞品教训（research/）：Stickies 死于用户卡在 setup 页,
/// Sticky Widgets 的 1★ 有「difficult to get the widget to post」——
/// 第三步的 widget 添加引导因此是横幅提示而非阻断步骤。
enum OnboardingGate {

    private static let widgetHintKey = "onboarding.widgetHintShown"

    /// 首启判定：无选中宠物且无便签。
    static func shouldShowOnboarding(hasSelectedPet: Bool, noteCount: Int) -> Bool {
        !hasSelectedPet && noteCount == 0
    }

    /// widget 添加引导是否已展示过（一次性,设备级持久）。
    static var widgetHintShown: Bool {
        get { UserDefaults.standard.bool(forKey: widgetHintKey) }
        set { UserDefaults.standard.set(newValue, forKey: widgetHintKey) }
    }
}
