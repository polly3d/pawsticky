import Foundation
import Core

/// Widget 进程的数据读取入口（W4-0 / W5 升级）。
///
/// Widget target 通过此类型读取 App Group 数据库的便签数据。
/// 所有读取都是同步的（Widget body 计算在主线程，不能 await）。
///
/// W5 升级：支持 CycleNoteIntent 的「当前便签」索引，从 WidgetPreferences 读取。
struct WidgetDataProvider {
    private let store: SharedStore?

    init() {
        store = SharedStore.cachedAppGroup()
    }

    /// 当前 Widget 应展示的便签（根据 CycleNoteIntent 的翻页状态）。
    func currentNote() -> Note? {
        let notes = allNotes()
        guard !notes.isEmpty else { return nil }
        let index = WidgetPreferences.clampedIndex(noteCount: notes.count)
        return notes[index]
    }

    /// 全部便签（按 position 排序）。
    func allNotes() -> [Note] {
        guard let store else { return [] }
        return (try? store.allNotes()) ?? []
    }

    /// 指定便签的清单项（按 position 排序）。
    func noteItems(noteId: UUID) -> [NoteItem] {
        guard let store else { return [] }
        return (try? store.noteItems(noteId: noteId)) ?? []
    }

    /// 便签总数。
    func noteCount() -> Int {
        guard let store else { return 0 }
        return (try? store.countNotes()) ?? 0
    }
}
