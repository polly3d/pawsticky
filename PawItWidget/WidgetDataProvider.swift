import Foundation
import Core

/// Widget 进程的数据读取入口（W4-0）。
///
/// Widget target 通过此类型读取 App Group 数据库的便签数据。
/// 所有读取都是同步的（Widget body 计算在主线程，不能 await），
/// 经 SharedStore 的 GRDB pool.read 完成。
///
/// 设计决策：
/// - 每次 body 计算都读最新数据（不缓存），确保 intent 交互后重绘拿到新值
/// - 失败时返回空/默认值，Widget 降级为空状态而非崩溃
struct WidgetDataProvider {
    private let store: SharedStore?

    init() {
        store = SharedStore.cachedAppGroup()
    }

    /// 当前「第一条便签」（position 排序首条），Widget 默认展示的数据源。
    func firstNote() -> Note? {
        guard let store else { return nil }
        return try? store.firstNote()
    }

    /// 全部便签（按 position 排序），Medium/Large Widget 可展示多条。
    func allNotes() -> [Note] {
        guard let store else { return [] }
        return (try? store.allNotes()) ?? []
    }

    /// 指定便签的清单项（按 position 排序）。
    func noteItems(noteId: UUID) -> [NoteItem] {
        guard let store else { return [] }
        return (try? store.noteItems(noteId: noteId)) ?? []
    }

    /// 便签总数（用于锁屏 inline 等极简展示）。
    func noteCount() -> Int {
        guard let store else { return 0 }
        return (try? store.countNotes()) ?? 0
    }
}
