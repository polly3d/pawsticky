import AppIntents
import Foundation

/// PoC A（Task 2）：交互式 Widget 的 AppIntent。
/// 用户在 Widget 上轻点 → 系统在 Widget 扩展进程内执行 perform() →
/// 翻转 App Group 中的共享状态 → WidgetKit 自动重绘（无需拉起主 App）。
public struct ToggleItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Item"

    public init() {}

    public func perform() async throws -> some IntentResult {
        ToggleState.toggle()
        // 返回后系统自动重绘发起调用的 Widget（交互式 Widget 内建行为）。
        return .result()
    }
}
