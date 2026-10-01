import Foundation

// MARK: - ChecklistProgress（P1-3 DRY：清单进度的单一定义点）

/// 可勾选条目——跨三端 DTO 的进度计算收敛。
/// 三端元素类型不同（`NoteItem` / `WatchPayload.ItemSnapshot` /
/// `NoteActivityAttributes.ChecklistItem`），「x/y 完成」与进度环的算法此前
/// 内联重复 10 处；本协议只暴露 `isDone`，算法统一收敛到 Sequence 扩展。
/// 刻意不继承 Sendable：LA 的 `ChecklistItem` 定义在 Shared/（不 import Core），
/// retroactive Sendable conformance 受 Swift 6 同文件规则限制——各具体类型的
/// Sendable 由其自身声明保证，协议侧无需重复要求。
public protocol Checkable {
    var isDone: Bool { get }
}

extension NoteItem: Checkable {
    public var isDone: Bool { done }
}

extension WatchPayload.ItemSnapshot: Checkable {
    public var isDone: Bool { done }
}

extension Sequence where Element: Checkable {

    /// 已完成条数。
    public var doneCount: Int {
        reduce(0) { $0 + ($1.isDone ? 1 : 0) }
    }

    /// 完成率（0...1）；空清单按 0（无进度而非满进度）。
    public var completionFraction: Double {
        var done = 0
        var total = 0
        for item in self {
            total += 1
            if item.isDone { done += 1 }
        }
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}
