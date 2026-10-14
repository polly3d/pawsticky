import AppIntents
import Foundation
import GRDB
import WidgetKit

/// Siri / 快捷指令速记（W5-2）："Hey Siri, add Buy cat food to PawSticky"。
///
/// 创建新便签，position 追加到队尾（MAX+1）。
/// Widget 进程直写 SharedStore（不走 NoteRepository、不落历史）。
public struct AppendNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Note"
    public static let description: IntentDescription = "Create a new note in PawSticky"

    /// Siri 会提示用户输入此参数。
    @Parameter(title: "Note text")
    public var text: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = SharedStore.cachedAppGroup() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Please provide some text for the note.")
        }

        // position = MAX(position) + 1（追加队尾，与 NoteRepository.createNote 同一语义）
        try await store.write { db in
            let maxPos = try Int.fetchOne(db, Note.select(max(Column("position")))) ?? -1
            let note = Note(text: trimmed, position: maxPos + 1)
            try note.insert(db)
        }

        // Siri/Shortcuts 入口没有交互式 widget 按钮的系统自动重绘——必须显式
        // reload,否则新便签要等下次 App 前后台切换才出现在 widget。
        // Watch 同步:本进程无 WCSession 会话(归主 App),App 下次回前台时
        // scenePhase → .active 的 syncToWatch 会补上。
        WidgetCenter.shared.reloadAllTimelines()

        return .result(dialog: "Added: \(trimmed)")
    }
}
