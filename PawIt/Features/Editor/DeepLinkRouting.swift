import Foundation
import Observation
import Core

/// 站内跳转的「落点翻译」：把一个跳转目标翻成「编辑器该怎么开」。
///
/// 纯函数——冷启动 / 热启动的时序、别的 sheet 要不要先收起，都由调用方（`NoteListView`）处理，
/// 这里只做决策，所以能脱离界面单测。
enum DeepLinkResolver {

    /// - Parameters:
    ///   - onboardingNeeded: 首次引导是否还没走完（调用方用 `OnboardingGate` 现算，
    ///     不能依赖 `showOnboarding`：冷启动时跳转处理可能先于引导的触发）。
    ///   - noteExists: 便签此刻是否还在库里。
    /// - Returns: 要打开的编辑器模式；nil = 什么都不做（停在列表页）。
    static func editorMode(
        for link: DeepLink,
        onboardingNeeded: Bool,
        noteExists: (UUID) -> Bool
    ) -> EditorMode? {
        // 引导最后本来就会把用户带进新建页；此时再弹编辑器会和引导全屏页打架
        guard !onboardingNeeded else { return nil }

        switch link {
        case .newNote:
            return .create
        case .openNote(let id):
            // 小组件的快照可能比库旧：便签在 App 里已被删时，不开一个空编辑器
            return noteExists(id) ? .edit(id) : nil
        }
    }
}

/// 站内跳转的中转站：`onOpenURL` 收到的链接先挂在这里，由列表页取走。
///
/// 为什么要中转而不是直接改界面状态：冷启动时（用户点小组件把 App 拉起来），
/// `onOpenURL` 的触发可能早于列表页就绪；直接发通知会丢，挂起再由列表页在出现时取走则不会。
@MainActor @Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()

    /// 待处理的跳转；列表页取走后清空。
    var pending: DeepLink?

    /// 接收一个外部 URL；不认识的静默丢弃（也不会冲掉尚未处理的有效链接）。
    func receive(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        pending = link
    }
}
