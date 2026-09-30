import Foundation
import GRDB

/// PawIt 跨 target 共享的常量与基础模型（纯逻辑层，无 UI 依赖）。

public enum PawItInfo {
    /// 三 target（App / Widget / Watch）共享的 App Group 标识。
    public static let appGroupID = "group.com.pawit.shared"
}

/// 一条宠物便签，对应 note 表（W1 最小 schema：id TEXT PK, text, createdAt, done）。
/// Task 3 将骨架期占位模型（title/body）演进为与数据库列一一对应的 GRDB 记录。
public struct Note: Equatable, Sendable, FetchableRecord, PersistableRecord {
    /// 数据库表名（GRDB）。
    public static let databaseTableName = "note"

    public let id: UUID
    /// 便签正文（W1 单字段；真实 schema 由 W2 演进）。
    public var text: String
    public var createdAt: Date
    /// 勾选标记——Widget 开关状态的真实来源。
    public var done: Bool

    public init(id: UUID = UUID(), text: String, createdAt: Date = .now, done: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.done = done
    }
}

extension Note {
    /// GRDB 手工列映射：id 以 TEXT（uuidString）持久化，与 schema 的 `id TEXT PK` 对齐。
    public init(row: Row) throws {
        let rawID: String = row["id"]
        guard let parsedID = UUID(uuidString: rawID) else {
            throw SharedStoreError.corruptNoteID(rawID)
        }
        id = parsedID
        text = row["text"]
        createdAt = row["createdAt"]
        done = row["done"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["text"] = text
        container["createdAt"] = createdAt
        container["done"] = done
    }
}
