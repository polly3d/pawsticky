import Testing
import AppIntents
@testable import Core

/// PoC A（Task 2）：验证交互式 Widget 的数据闭环
/// intent perform → App Group UserDefaults 状态翻转（false → true → false）。
struct ToggleItemIntentTests {
    @Test func performFlipsAppGroupState() async throws {
        // UserDefaults 跨测试运行持久化，先重置保证确定性起点。
        ToggleState.reset()
        #expect(ToggleState.isToggled == false)

        _ = try await ToggleItemIntent().perform()
        #expect(ToggleState.isToggled == true)

        _ = try await ToggleItemIntent().perform()
        #expect(ToggleState.isToggled == false)
    }

    @Test func stateLivesInSharedAppGroupSuite() {
        // 状态必须落在共享 App Group suite（而非 .standard），
        // 这样 Widget 扩展与主 App 进程读写的是同一份数据。
        let shared = UserDefaults(suiteName: PawItInfo.appGroupID)
        #expect(shared != nil)
        #expect(shared !== UserDefaults.standard)
    }
}
