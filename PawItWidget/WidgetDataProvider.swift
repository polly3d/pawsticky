import Foundation
import Core
import os

/// Widget 进程的数据读取入口（W4-0 / W5 升级 / P1-1 数据快照化）。
///
/// P1-1 升级：数据在 `getTimeline` 阶段经 `fetchContent()` 一次抓取进 entry，
/// 渲染层（view body）零 DB 查询——此前 6 个家族的 body 每次渲染 6-7 次
/// 同步查询（计算属性每次访问都打库）。失败路径不再静默（P1-5）：os_log 输出诊断。
struct WidgetDataProvider {
    private let store: SharedStore?

    private static let logger = Logger(subsystem: "com.pawit.app", category: "widgetData")

    init() {
        store = SharedStore.cachedAppGroup()
    }

    /// 一次渲染所需的全部数据快照（provider 阶段抓取，随 entry 进入渲染层）。
    func fetchContent() -> WidgetContent {
        guard let store else { return .empty }
        do {
            let notes = try store.allNotes()
            guard !notes.isEmpty else {
                return WidgetContent(
                    note: nil, items: [],
                    pet: try store.selectedPet(), noteCount: 0
                )
            }
            // 「当前便签」按 CycleNoteIntent 的翻页索引定位（与 intent 同一裁决）。
            let index = WidgetPreferences.clampedIndex(noteCount: notes.count)
            let note = notes[index]
            return WidgetContent(
                note: note,
                items: try store.noteItems(noteId: note.id),
                pet: try store.selectedPet(),
                noteCount: notes.count
            )
        } catch {
            Self.logger.warning(
                "fetchContent 读取失败: \(String(describing: error), privacy: .public)"
            )
            return .empty
        }
    }
}

/// 渲染所需的不可变数据包——「数据在 provider 抓取、渲染是纯函数」的载体。
struct WidgetContent {
    /// 当前展示的便签（nil = 空库）。
    var note: Note?
    /// 当前便签的清单项（position 序）。
    var items: [NoteItem]
    /// 当前选中的宠物。
    var pet: PetProfile?
    /// 便签总数（翻页指示用）。
    var noteCount: Int

    static let empty = WidgetContent(note: nil, items: [], pet: nil, noteCount: 0)

    /// 便签颜色预设（解析单一入口 `NoteStylePreset.resolve`）。
    var preset: NoteStylePreset { NoteStylePreset.resolve(note?.style) }

    /// 是否有多条便签（翻页按钮的显隐）。
    var hasMultipleNotes: Bool { noteCount > 1 }
}
