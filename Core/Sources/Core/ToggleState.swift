import Foundation

/// PoC A（Task 2）专用的最小开关状态：存放在共享 App Group 的 UserDefaults 里，
/// 跨进程（App / Widget 扩展）可见。真正的 GRDB SharedStore 在 Task 3 落地后替换。
///
/// 用 enum 命名空间 + 每次访问现取 `UserDefaults` 实例的方式实现，
/// 无共享可变状态，天然满足 Swift 6 严格并发（Sendable）要求。
public enum ToggleState {
    /// App Group defaults 内的存储键（internal，供测试层 @testable 访问）。
    static let storageKey = "poc.isToggled"

    /// 每次读取现取 suite 实例（Foundation 内部有缓存，开销可忽略）。
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: PawItInfo.appGroupID)
    }

    /// 当前是否已勾选。suite 不可用时按未勾选处理。
    public static var isToggled: Bool {
        defaults?.bool(forKey: storageKey) ?? false
    }

    /// 翻转勾选状态并立即持久化。
    public static func toggle() {
        defaults?.set(!isToggled, forKey: storageKey)
    }

    /// 清除持久化状态（测试用，保证运行间确定性）。
    static func reset() {
        defaults?.removeObject(forKey: storageKey)
    }
}
