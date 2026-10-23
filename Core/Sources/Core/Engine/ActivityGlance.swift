import Foundation

// MARK: - ActivityGlance（Live Activity 小卡片的“一瞥”）

/// 带文字的可勾选条目。
///
/// 在 `Checkable`（只有 `isDone`）之上多要一个 `text`——“下一件做什么”要把文字亮出来。
/// 真实元素是 Widget 里的 `NoteActivityAttributes.ChecklistItem`（定义在 Shared/、不 import Core，
/// 由 Widget 文件里的 extension 补上本协议）。
public protocol TextCheckable: Checkable {
    var text: String { get }
}

/// Live Activity 小尺寸卡片（Apple Watch 智能叠放 / CarPlay，`.small` 家族）要展示的“一瞥”。
///
/// 画布最小只有 152×69.5pt（40mm 手表），放不下整张清单，只回答三件事：
/// 做到哪了（进度环 + x/y）→ 下一件做什么 → 再后面还有什么。
/// 放在 Core 而不是视图里，是为了让“算什么、怎么算”能被单测钉住；视图只管把结果画出来。
public struct ActivityGlance: Equatable, Sendable {

    /// 清单总条数（含空白条目——它确实占一格，分母不能少算）。
    public let total: Int
    /// 已勾选条数（如实反映，不受 `noteIsDone` 影响）。
    public let done: Int
    /// 是否按“完成”呈现：整条便签被标成已完成，或清单非空且全部勾完。
    public let isComplete: Bool
    /// 下一件要做的事：清单顺序里第一个没勾的非空条目；完成态为 nil。
    public let next: String?
    /// `next` 之后再往后的几件事（最多 `upcomingLimit` 条）；完成态为空。
    public let upcoming: [String]

    /// - Parameters:
    ///   - items: 便签清单（可为空 = 普通便签）。
    ///   - noteIsDone: 整条便签是否被标成已完成。
    ///   - upcomingLimit: 后续项最多取几条。小卡片只有“一瞥”的空间，默认 2。
    public init<S: Sequence>(
        items: S,
        noteIsDone: Bool,
        upcomingLimit: Int = 2
    ) where S.Element: TextCheckable {
        let all = Array(items)
        total = all.count
        done = all.doneCount
        isComplete = noteIsDone || (all.count > 0 && done == all.count)

        guard !isComplete else {
            next = nil
            upcoming = []
            return
        }
        // 空白条目显示成 "Next: "（后面什么都没有）很怪，所以不当作下一项 / 后续项
        let pending = all
            .filter { !$0.isDone }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        next = pending.first
        upcoming = Array(pending.dropFirst().prefix(max(upcomingLimit, 0)))
    }

    /// 进度环填充比例（0...1）。
    ///
    /// - `nil`：没有清单（普通便签）——不画环，只放大头像；
    /// - `0`：有清单但还没开始——画一个空环。两者是两回事，所以用可选值区分，而不是都给 0。
    /// - 完成态一律按 1（整条便签被直接标成完成时，即使还有条目没勾也画满环）。
    public var ringFraction: Double? {
        guard total > 0 else { return nil }
        return isComplete ? 1 : Double(done) / Double(total)
    }
}
