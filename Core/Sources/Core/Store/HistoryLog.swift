import Foundation
import GRDB

// MARK: - HistoryLog(W2-4):append-only 回滚日志
//
// 「零丢数据」承诺的存储半边:每次实体变更都在**同一写事务**内落一条整行快照,
// 保留窗 7 天,窗内任意快照可回滚(`NoteRepository.restore`)。
//
// 写入纪律(schema 侧契约见 `SharedStore.registerW2V2`):
// 只 INSERT(变更)与 DELETE(保留期清理),**永不 UPDATE**——条目一经落盘不可变。
//
// **快照语义(决策记录)**:payload = 该实体变更时刻的整行 JSON。
// * 更新/删除类变更取 **PRE-change 前像**——回滚就是把前像写回去,这正是
//   「误删找回 / 改坏了还原」的主路径,前像是唯一可用的快照时机;
// * 创建类变更(行此前不存在)取**后像**(新出现的行)——前像是「缺席」,
//   有用的记录就是出现了什么;误删该行时其删除前像另有条目兜底。
// * 快照编码与导出格式共用同一套 DTO(`ExportFormat.swift`,移交项⑦的单一编码路径):
//   history_log 因此天然是导出格式的行级子集,未来「按条目导出」零额外编码。

/// 历史条目的实体类型;rawValue 即 history_log.entityType 的存储值。
public enum HistoryEntityType: String, Equatable, Sendable, Codable, Hashable {
    case note
    case noteItem
    case petProfile
    case growthState
}

/// history_log 一行:某实体一次变更时刻的整行 JSON 快照。
/// `entityId` 存储真值是 String(便签/清单项为 `uuidString`,宠物/养成状态为其 String id)。
public struct HistoryEntry: Equatable, Sendable, FetchableRecord, PersistableRecord {
    /// 数据库表名(GRDB)。
    public static let databaseTableName = "history_log"

    public let id: UUID
    public var entityType: HistoryEntityType
    public var entityId: String
    /// 整行快照 JSON(编码走导出 DTO,见 `ExportFormat.swift`)。
    public var payload: String
    public var changedAt: Date

    public init(
        id: UUID,
        entityType: HistoryEntityType,
        entityId: String,
        payload: String,
        changedAt: Date
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.changedAt = changedAt
    }
}

extension HistoryEntry {
    /// GRDB 手工列映射:id/entityType 以 TEXT(rawValue)持久化,changedAt 走 `.datetime`。
    public init(row: Row) throws {
        id = try UUID.parseStorage(row["id"])
        let rawType: String = row["entityType"]
        guard let type = HistoryEntityType(rawValue: rawType) else {
            throw SharedStoreError.corruptHistoryEntityType(rawType)
        }
        entityType = type
        entityId = row["entityId"]
        payload = row["payload"]
        changedAt = row["changedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["entityType"] = entityType.rawValue
        container["entityId"] = entityId
        container["payload"] = payload
        container["changedAt"] = changedAt
    }
}

/// 日志机制本体:追加(含保留期清理)与按实体取数。
/// 全部函数都要求调用方已持有**写事务内的 `Database` 连接**——历史与变更同生共死
/// 是 `NoteRepository` 的原子性契约,本层不做第二事务。
public enum HistoryLog {

    /// 保留窗:7 天(plan W2-4「7 天 append-only 回滚日志」)。
    /// 过期条目由下一次 append 顺手清走(见 `append`),无后台定时器。
    public static let retentionInterval: TimeInterval = 7 * 24 * 3600

    /// 在当前写事务内追加一条快照,并顺手清走保留窗外的过期条目。
    /// - Parameters:
    ///   - now: 条目时刻(默认真实墙钟; retention 截止线随之推导)。
    /// - Returns: 已落库的条目(其 `id` 供后续 `restore` 寻址)。
    @discardableResult
    public static func append(
        in db: Database,
        entityType: HistoryEntityType,
        entityId: String,
        payload: String,
        now: Date = .now
    ) throws -> HistoryEntry {
        let entry = HistoryEntry(
            id: UUID(),
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            changedAt: now
        )
        try entry.insert(db)
        // 保留期清理:只 DELETE `changedAt` 过期的行——这是 retention(数据治理),
        // 不是对记录的修订;append-only 纪律(永不 UPDATE)不受影响。
        try prune(in: db, olderThan: now.addingTimeInterval(-retentionInterval))
        return entry
    }

    /// 清理 `cutoff` 之前的条目(严格小于)。独立成函数供测试与未来的手动清理复用。
    public static func prune(in db: Database, olderThan cutoff: Date) throws {
        try db.execute(sql: "DELETE FROM history_log WHERE changedAt < ?", arguments: [cutoff])
    }

    /// 某实体的全部在窗条目,最新在前。
    /// 排序:`changedAt` DESC,同毫秒并列时以插入序(`rowid`)DESC 决胜——
    /// 同一事务内连落多条(如 deleteNote 的便签+清单项)顺序确定,与 UUID 随机性无关。
    public static func entries(
        entityType: HistoryEntityType,
        entityId: String,
        in db: Database
    ) throws -> [HistoryEntry] {
        try HistoryEntry
            .filter(Column("entityType") == entityType.rawValue)
            .filter(Column("entityId") == entityId)
            .order(sql: "changedAt DESC, rowid DESC")
            .fetchAll(db)
    }

    /// 某实体的最新一条条目——`entries` 的 LIMIT 1 形态(同序契约:
    /// `changedAt` DESC, `rowid` DESC)。「只看最新」的调用(如会话合并的
    /// 窗口裁决)走此查询,不为一条数据搬全量数组——编辑器活跃时每次
    /// 防抖落盘都会经过这里(~3 次/秒)。
    public static func latestEntry(
        entityType: HistoryEntityType,
        entityId: String,
        in db: Database
    ) throws -> HistoryEntry? {
        try HistoryEntry
            .filter(Column("entityType") == entityType.rawValue)
            .filter(Column("entityId") == entityId)
            .order(sql: "changedAt DESC, rowid DESC")
            .fetchOne(db)
    }
}
