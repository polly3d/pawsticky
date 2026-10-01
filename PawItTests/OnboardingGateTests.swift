import Testing
import Foundation
@testable import PawIt

/// Onboarding 首启判定的行为钉子（方案 A:数据驱动,无独立首启标记可漂移）。
struct OnboardingGateTests {

    // MARK: - 首启判定

    @Test func onboardingShowsOnlyWhenNoPetAndNoNotes() {
        // 无宠无签 = 全新安装 → 引导
        #expect(OnboardingGate.shouldShowOnboarding(hasSelectedPet: false, noteCount: 0))
        // 宠物一经选择(不可删除)即永不再触发——中途退出的用户落在正常空状态
        #expect(!OnboardingGate.shouldShowOnboarding(hasSelectedPet: true, noteCount: 0))
        // 已有便签(如经导入/Siri 速记进入)不引导
        #expect(!OnboardingGate.shouldShowOnboarding(hasSelectedPet: false, noteCount: 3))
        #expect(!OnboardingGate.shouldShowOnboarding(hasSelectedPet: true, noteCount: 3))
    }

    // MARK: - widget 引导横幅的一次性标记

    @Test func widgetHintFlagRoundTrips() {
        let key = "onboarding.widgetHintShown"
        UserDefaults.standard.removeObject(forKey: key)

        #expect(!OnboardingGate.widgetHintShown, "默认未展示")

        OnboardingGate.widgetHintShown = true
        #expect(UserDefaults.standard.bool(forKey: key), "必须落 UserDefaults(跨启动持久)")
        #expect(OnboardingGate.widgetHintShown)

        // 复位,避免污染其它测试
        OnboardingGate.widgetHintShown = false
        UserDefaults.standard.removeObject(forKey: key)
    }
}
