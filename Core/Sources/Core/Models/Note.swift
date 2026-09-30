import Foundation
import GRDB

/// 一条宠物便签,对应 note 表(W2 schema:id TEXT PK, text, createdAt, done, dueDate, position)。
/// W2-2 起在 W1 四列之上 additive 增加 `dueDate`(可空到期日)与 `position`(手动排序);
/// 迁移只增不改,w1 存量行由 `w2.v1` 默认值补齐(position 0、dueDate NULL)。
public struct Note: Equatable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    /// 数据库表名(GRDB)。
    public static let databaseTableName = "note"

    public let id: UUID
    /// 便签正文。
    public var text: String
    public var createdAt: Date
    /// 勾选标记——Widget 开关状态的真实来源。
    public var done: Bool
    /// 到期提醒时刻(W3 本地通知的数据基础);nil = 未设到期。
    public var dueDate: Date?
    /// 手动排序键,小者在前;同值时依 (createdAt, id) 决胜(见 `SharedStore.allNotes()`)。
    public var position: Int
    /// 颜色预设（W3-1）;nil = classicYellow 默认。存 `NoteStylePreset.rawValue`。
    public var style: String?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        done: Bool = false,
        dueDate: Date? = nil,
        position: Int = 0,
        style: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.done = done
        self.dueDate = dueDate
        self.position = position
        self.style = style
    }
}

extension Note {
    /// GRDB 手工列映射:id 以 TEXT(uuidString)持久化,与 schema 的 `id TEXT PK` 对齐;
    /// 日期列全部为 GRDB `.datetime`(GRDB 默认把 Date 持久化为
    /// "YYYY-MM-DD HH:MM:SS.SSS" 文本,与 w1 的 createdAt 同族编码)。
    /// id 解析走 `UUID.parseStorage`(W2-4 移交项⑧ DRY)。
    public init(row: Row) throws {
        let rawID: String = row["id"]
        id = try UUID.parseStorage(rawID)
        text = row["text"]
        createdAt = row["createdAt"]
        done = row["done"]
        dueDate = row["dueDate"]
        position = row["position"]
        style = row["style"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["text"] = text
        container["createdAt"] = createdAt
        container["done"] = done
        container["dueDate"] = dueDate
        container["position"] = position
        container["style"] = style
    }
}

extension Note {
    /// 本便签下的清单项(非存储列,现查):按 (position, id) 升序,
    /// 与 `SharedStore.noteItems(noteId:)` 同一排序契约。
    public func items(in db: Database) throws -> [NoteItem] {
        try NoteItem
            .filter(Column("noteId") == id.uuidString)
            .order(Column("position").asc, Column("id").asc)
            .fetchAll(db)
    }
}
