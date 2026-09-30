import Foundation
import GRDB

/// 便签内的一条清单项,对应 note_item 表(W2 新增)。
/// 外键 `noteId REFERENCES note(id) ON DELETE CASCADE`:删便签连带清空其事项
/// (见 `SharedStore.deleteNote(id:)` 与 SchemaTests 的级联断言)。
public struct NoteItem: Equatable, Sendable, FetchableRecord, PersistableRecord {
    /// 数据库表名(GRDB)。
    public static let databaseTableName = "note_item"

    public let id: UUID
    /// 所属便签(id 与 Note.id 同为 UUID→TEXT 编码)。
    public var noteId: UUID
    /// 清单项正文(如「铲屎」)。
    public var text: String
    /// 勾选标记——Widget 内单事项开关状态的真实来源。
    public var done: Bool
    /// 手动排序键,小者在前;同值时以 id ASC 决胜(见 `SharedStore.noteItems(noteId:)`)。
    public var position: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        text: String,
        done: Bool = false,
        position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.noteId = noteId
        self.text = text
        self.done = done
        self.position = position
        self.createdAt = createdAt
    }
}

extension NoteItem {
    /// GRDB 手工列映射:id/noteId 以 TEXT(uuidString)持久化,日期列 `.datetime` 文本编码。
    /// 两列均经 `UUID.parseStorage`(W2-4 移交项⑧ DRY;noteId 非主键同样复用
    /// `corruptNoteID` 错误)。
    public init(row: Row) throws {
        let rawID: String = row["id"]
        id = try UUID.parseStorage(rawID)
        let rawNoteID: String = row["noteId"]
        noteId = try UUID.parseStorage(rawNoteID)
        text = row["text"]
        done = row["done"]
        position = row["position"]
        createdAt = row["createdAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["noteId"] = noteId.uuidString
        container["text"] = text
        container["done"] = done
        container["position"] = position
        container["createdAt"] = createdAt
    }
}
