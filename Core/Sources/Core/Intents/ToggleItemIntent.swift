import AppIntents
import Foundation

/// Widget 内勾选（W5-0 升级版）：翻转当前展示便签的 done 标记。
///
/// W1 PoC 版 toggleFirstItem → W5 按 WidgetPreferences.currentNoteIndex 定位目标便签。
/// Widget 进程直写 SharedStore（不走 NoteRepository、不落历史——W2-4 移交项④既定决策）。
public struct ToggleItemIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Note"
    public static let description: IntentDescription = "Mark the current note as done or not done"

    public init() {}

    public func perform() async throws -> some IntentResult {
        guard let store = SharedStore.cachedAppGroup() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }

        let notes = try store.allNotes()
        guard !notes.isEmpty else { return .result() }

        let index = WidgetPreferences.clampedIndex(noteCount: notes.count)
        let targetNote = notes[index]

        try await store.toggleNote(id: targetNote.id)
        return .result()
    }
}
