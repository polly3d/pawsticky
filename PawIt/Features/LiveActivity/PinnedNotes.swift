import Foundation
import Observation

/// 列表里「哪些便签钉在锁屏上」的可观察状态——界面显示钉住图标的唯一来源。
///
/// **为什么需要它（C12）**：此前列表在 body 里直接问 ActivityKit（当时的 `LiveActivityManager.isPinned`）。
/// 那是一份**不可观察**的运行时状态，而 pin / unpin 又没有改动任何 SwiftUI 状态，
/// 所以点了 Pin 之后列表根本不知道该重绘——图标要等到「切走再回来 → `reloadNotes()`」
/// 顺带触发一次重绘才出现（unpin 同理，图标赖着不走）。
///
/// 现在的分工：pin / unpin 在发生的**当下**调 `didPin` / `didUnpin`，界面立刻更新；
/// 回前台、列表重载时调 `refresh()` 与 ActivityKit 的真实状态对齐（用户在锁屏上划掉
/// Live Activity、系统到期收走、别的路径新建了 Activity，都靠这一步反映回来）。
///
/// **为什么要记 `ending`**：`Activity.end` 是异步的——实测 `unpin` 返回后 ActivityKit 仍报告
/// 「钉着」（6ms 时还在，约 500ms 后才变）。这段窗口里恰好来一次 `refresh()`（比如刚好回前台），
/// 照单全收的话，刚取消的图标会又「复活」，直到下一次对齐。所以已请求结束的便签，
/// 在系统真正报告它结束之前一律不显示。
@MainActor
@Observable
final class PinnedNotes {
    /// 当前显示为「已钉住」的便签 id。
    private var ids: Set<UUID> = []

    /// 已请求结束、但 ActivityKit 还没报告结束的便签。纯内部记账，不参与界面观察。
    @ObservationIgnored private var ending: Set<UUID> = []

    /// ActivityKit 现状的来源；测试里注入替身。
    @ObservationIgnored private let liveIDs: @MainActor () -> Set<UUID>

    init(liveIDs: @escaping @MainActor () -> Set<UUID> = { LiveActivityManager.pinnedNoteIds() }) {
        self.liveIDs = liveIDs
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    /// 与 ActivityKit 的真实状态对齐。
    func refresh() {
        let live = liveIDs()
        // 系统已经报告结束的，不用再「压着」了
        ending.formIntersection(live)
        ids = live.subtracting(ending)
    }

    /// 刚把便签钉上（`LiveActivityManager.pin` 成功返回之后调用）。
    func didPin(_ id: UUID) {
        ending.remove(id)
        ids.insert(id)
    }

    /// 刚请求取消钉住（`LiveActivityManager.unpin` 之后调用）。
    func didUnpin(_ id: UUID) {
        ids.remove(id)
        ending.insert(id)
    }
}
