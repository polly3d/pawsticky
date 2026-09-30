import AppIntents
import Foundation
import GRDB

/// Siri / 快捷指令速记（W5-2）："Hey Siri, add Buy cat food to PawIt"。
///
/// 创建新便签，position 追加到队尾（MAX+1）。
/// Widget 进程直写 SharedStore（不走 NoteRepository、不落历史）。
public struct AppendNoteIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Note"
    public static let description: IntentDescription = "Create a new note in PawIt"

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

        return .result(dialog: "Added: \(trimmed)")
    }
}
