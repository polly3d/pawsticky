import Testing
import Foundation
import os
@testable import PawIt

/// C12（真机发现）：便签 pin 之后，列表里的钉住图标不立刻出现（unpin 之后也不立刻消失），要重进 App 才更新。
///
/// 根因：界面在 body 里直接读 ActivityKit——那是不可观察的外部状态，pin / unpin 没有引起任何
/// SwiftUI 状态变化，列表就不重绘。`PinnedNotes` 是这份状态的可观察持有者；这里钉住它的契约：
/// 读它的界面一定会被通知；unpin 的异步收尾期间（实测 ≈ 500ms）不会被「对齐」拉回来。
@MainActor
struct PinnedNotesTests {

    private let a = UUID()
    private let b = UUID()

    /// 可控的「ActivityKit 现状」替身：测试里改它，模拟系统侧的变化。
    private final class Live {
        var ids: Set<UUID> = []
    }

    private func model(_ live: Live) -> PinnedNotes {
        PinnedNotes { live.ids }
    }

    // MARK: - 与系统状态对齐

    @Test func refreshShowsWhatTheSystemReports() {
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        #expect(!pinned.contains(a))  // 没对齐之前什么都不显示（init 不读 ActivityKit）
        pinned.refresh()
        #expect(pinned.contains(a))
        #expect(!pinned.contains(b))
    }

    @Test func refreshDropsActivitiesTheSystemHasEnded() {
        // 用户在锁屏上划掉了 Live Activity，或系统到期收掉了它
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        #expect(pinned.contains(a))
        live.ids = []
        pinned.refresh()
        #expect(!pinned.contains(a))
    }

    // MARK: - pin / unpin 当下就生效

    @Test func pinningShowsTheNoteImmediatelyWithoutWaitingForARefresh() {
        let pinned = model(Live())
        pinned.didPin(a)
        #expect(pinned.contains(a))
    }

    @Test func unpinningHidesTheNoteImmediatelyEvenThoughTheSystemStillReportsIt() {
        // 实测：unpin() 返回后 6ms 内 ActivityKit 仍报告「钉着」，约 500ms 后才变
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        #expect(pinned.contains(a))
        pinned.didUnpin(a)
        #expect(!pinned.contains(a))
    }

    // MARK: - unpin 的异步收尾期间

    @Test func aRefreshWhileTheEndIsInFlightDoesNotBringTheIconBack() {
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        #expect(pinned.contains(a))
        pinned.didUnpin(a)
        pinned.refresh()  // 系统还没收完：live 里仍有 a
        #expect(!pinned.contains(a))
    }

    @Test func onceTheEndHasFinishedTheNoteCanBePinnedAgain() {
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        #expect(pinned.contains(a))
        pinned.didUnpin(a)
        live.ids = []  // 系统收完了
        pinned.refresh()
        #expect(!pinned.contains(a))
        live.ids = [a]  // 再次钉住（新的 Activity）
        pinned.refresh()
        #expect(pinned.contains(a))
    }

    @Test func pinningAgainDuringTheEndWindowShowsTheNote() {
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        pinned.didUnpin(a)
        pinned.didPin(a)
        #expect(pinned.contains(a))
        pinned.refresh()  // 对齐不能再把它压下去
        #expect(pinned.contains(a))
    }

    // MARK: - 读它的界面会被通知（「列表会重绘」的单测形态）

    /// 读 `contains` 的界面，在 `change` 之后必须收到通知。
    private func notifies(
        _ pinned: PinnedNotes, reading id: UUID, whenYouDo change: () -> Void
    ) -> Bool {
        let fired = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = pinned.contains(id)
        } onChange: {
            fired.withLock { $0 = true }
        }
        change()
        return fired.withLock { $0 }
    }

    @Test func pinningNotifiesViewsThatReadTheNote() {
        let pinned = model(Live())
        #expect(notifies(pinned, reading: a) { pinned.didPin(a) })
    }

    @Test func unpinningNotifiesViewsThatReadTheNote() {
        let live = Live()
        live.ids = [a]
        let pinned = model(live)
        pinned.refresh()
        #expect(pinned.contains(a))
        #expect(notifies(pinned, reading: a) { pinned.didUnpin(a) })
    }

    @Test func aRefreshThatChangesWhatIsPinnedNotifiesViews() {
        let live = Live()
        let pinned = model(live)
        live.ids = [a]
        #expect(notifies(pinned, reading: a) { pinned.refresh() })
    }
}
