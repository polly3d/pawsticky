import Foundation

/// Widget 状态持久化（App Group UserDefaults）——轻量键值，不入 SQLite。
///
/// Widget 的「当前展示第几条便签」需要在多次 timeline 渲染之间保持。
/// UserDefaults(suiteName: appGroupID) 是最轻量的选项：
/// - 同一 App Group，App 和 Widget 进程都可读写
/// - 不需要数据库事务（只是一个 index）
/// - intent perform 后写入，下次渲染时读取
public enum WidgetPreferences {

    private nonisolated(unsafe) static let defaults = UserDefaults(suiteName: PawItInfo.appGroupID)

    private static let currentNoteIndexKey = "widget.currentNoteIndex"

    /// 当前 Widget 展示的便签索引（在 allNotes 排序中的位置）。
    public static var currentNoteIndex: Int {
        get { defaults?.integer(forKey: currentNoteIndexKey) ?? 0 }
        set { defaults?.set(newValue, forKey: currentNoteIndexKey) }
    }

    /// 推进到下一条便签（循环），返回新的 index。
    /// - Parameter noteCount: 当前便签总数。
    /// - Returns: 循环后的新 index（总数为 0 时返回 0）。
    @discardableResult
    public static func advanceToNextNote(noteCount: Int) -> Int {
        guard noteCount > 0 else {
            currentNoteIndex = 0
            return 0
        }
        let next = (currentNoteIndex + 1) % noteCount
        currentNoteIndex = next
        return next
    }

    /// 确保 index 不越界（便签被删后 index 可能超出范围）。
    public static func clampedIndex(noteCount: Int) -> Int {
        guard noteCount > 0 else { return 0 }
        let idx = currentNoteIndex
        if idx >= noteCount {
            currentNoteIndex = 0
            return 0
        }
        return idx
    }
}
