import AppIntents
import Foundation

/// 交互式 Widget 的 AppIntent。Task 3 起数据落 App Group GRDB 库（WAL 双进程可见），
/// 替换 PoC A（Task 2）的 UserDefaults 桥（ToggleState，已删除）。
/// 用户在 Widget 上轻点 → 系统在 Widget 扩展进程内执行 perform() →
/// 原子翻转共享库中第一条便签的勾选状态 → WidgetKit 自动重绘（无需拉起主 App）。
public struct ToggleItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Item"

    public init() {}

    public func perform() async throws -> some IntentResult {
        // 进程级单池（W2-1 评审项 1）：同一扩展进程的多次 tap 复用一个 DatabasePool，
        // 修掉「每次 tap 重新开池」的 churn。失败零缓存（评审项 3）：本次 nil 不影响
        // 下次 tap 自动重试。读-改-写在同一事务内原子完成；busyTimeout 兜底跨进程写冲突。
        guard let store = SharedStore.cachedAppGroup() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }
        try await store.toggleFirstItem()
        // 返回后系统自动重绘发起调用的 Widget（交互式 Widget 内建行为）。
        return .result()
    }
}
