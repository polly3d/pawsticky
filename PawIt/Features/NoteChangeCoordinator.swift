import Foundation
import WidgetKit
import Core

/// 变更副作用单点（P1-2）：便签变更后的跨表面同步集中于此。
///
/// 此前「reload + Watch 同步 + 锁屏补刷 + 喂养」散落在 NoteListView /
/// NoteEditorView 各调用点——widget intent 侧的缺口（喂养 / 锁屏不刷新）
/// 正是散落导致的漏抄。新表面接入时只调这里,不再手抄副作用链。
///
/// 平台边界（记录在案）：
/// - Live Activity 只能由主 App 进程更新——widget 进程的勾选无法实时刷新
///   锁屏,由 App 回前台时 `LiveActivityManager.handleAppForeground()` 补刷兜底;
/// - WCSession 归主 App——widget/intent 进程的变更在下一次 .active 同步时补上。
enum NoteChangeCoordinator {

    /// 便签内容变更后：Watch 同步 + 锁屏补刷（若钉住）。
    /// - Parameter noteId: 变更的便签；nil 表示无法定位（如新建流程），仅同步 Watch。
    static func noteChanged(noteId: UUID?) {
        PhoneSessionManager.shared.syncToWatch()
        if let noteId {
            LiveActivityManager.refreshFromStore(noteId: noteId)
        }
    }

    /// 便签删除后：Watch 同步 + 锁屏取消钉住——Live Activity 不能留着已删便签的残影。
    static func noteDeleted(noteId: UUID) {
        PhoneSessionManager.shared.syncToWatch()
        LiveActivityManager.unpin(noteId: noteId)
    }

    /// 整库被替换（备份恢复）之后：把库外状态一次性对齐到新数据。
    ///
    /// 逐条便签走 `noteChanged / noteDeleted` 会让 Watch 同步跑 N 次；这里提醒与锁屏钉住逐条处理，
    /// Watch 与小组件只刷新一次。
    static func storeReplaced(_ result: RestoreResult) async {
        let reminders = ReminderManager()
        let restoredIds = Set(result.restoredNotes.map(\.id))

        // ① 被替换掉的便签：撤掉它们的提醒与锁屏钉住，不留“幽灵”。
        for id in result.previousNoteIds.subtracting(restoredIds) {
            await reminders.cancelReminder(noteID: id)
            LiveActivityManager.unpin(noteId: id)
        }

        // ② 备份里的便签：按各自的到期日重排提醒；已钉住的锁屏内容刷新成备份里的版本。
        //    换机恢复时这台设备还没被问过通知权限——有未过期的到期日才在此刻（上下文清楚）询问。
        if result.restoredNotes.contains(where: { ($0.dueDate ?? .distantPast) > .now }) {
            await reminders.ensureAuthorization()
        }
        for note in result.restoredNotes {
            await reminders.syncReminder(for: note)
            LiveActivityManager.refreshFromStore(noteId: note.id)
        }

        // ③ Watch 与小组件各刷新一次。
        PhoneSessionManager.shared.syncToWatch()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
