import Foundation
import GRDB

/// App Group 容器内的跨进程共享存储（Task 3 / PoC B，D2「零丢数据」的落地点）。
///
/// - GRDB `DatabasePool`：自动启用 WAL 日志（单写多读），App / Widget 扩展两个进程
///   各持独立连接并发访问同一数据库文件；`DatabasePool` 本身 Sendable。
/// - `busyTimeout = 2s`：跨进程写冲突时挂起等待而非上抛 `SQLITE_BUSY`。
/// - 读取走同步 `read`（WAL 读不阻塞写，供 Widget 渲染等同步路径直接调用）；
///   写入走 `async write`（协作线程池，不阻塞调用方执行器）。
public struct SharedStore: Sendable {
    private let pool: DatabasePool

    /// 在指定路径打开（必要时创建）共享数据库；目录不存在时自动创建，首次运行自动建表。
    public init(databasePath: String) throws {
        let fileURL = URL(fileURLWithPath: databasePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        // 双进程写冲突容忍窗口：最多等 2s，超时才上抛 SQLITE_BUSY（GRDB 7 的 busyMode API）。
        configuration.busyMode = .timeout(2)

        let pool = try DatabasePool(path: databasePath, configuration: configuration)
        try Self.makeMigrator().migrate(pool)
        self.pool = pool
    }

    /// App Group 容器内的共享库路径（Application Support/pawit.sqlite3）。
    public static func appGroupDatabasePath() -> String? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PawItInfo.appGroupID)?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("pawit.sqlite3")
            .path
    }

    /// 生产入口：打开 App Group 容器内的共享数据库。
    public static func appGroup() throws -> SharedStore {
        guard let path = appGroupDatabasePath() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }
        return try SharedStore(databasePath: path)
    }

    // MARK: - Schema

    /// W1 最小迁移：note(id TEXT PK, text, createdAt, done)。真实 schema 由 W2 设计。
    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("w1.v1") { db in
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    // MARK: - 写入（async，协作式）

    /// 插入一条便签。
    public func insert(_ note: Note) async throws {
        try await pool.write { db in
            try note.insert(db)
        }
    }

    /// 翻转「第一条」便签的 done 标记；库里为空则先插入一条种子便签（done=false）。
    /// 读-改-写在同一写事务内原子完成，跨连接并发调用不丢失更新。
    /// - Returns: 本次操作后的 done 状态。
    @discardableResult
    public func toggleFirstItem() async throws -> Bool {
        try await pool.write { db in
            if var note = try Note.order(Column("createdAt").asc).fetchOne(db) {
                note.done.toggle()
                try note.update(db)
                return note.done
            }
            let seed = Note(text: "待办")
            try seed.insert(db)
            return seed.done
        }
    }

    // MARK: - 读取（同步，WAL 读不阻塞写）

    /// 便签总数。
    public func countNotes() throws -> Int {
        try pool.read { db in
            try Note.fetchCount(db)
        }
    }

    /// 「第一条」便签（createdAt 最早）。
    public func firstNote() throws -> Note? {
        try pool.read { db in
            try Note.order(Column("createdAt").asc).fetchOne(db)
        }
    }

    /// 「第一条」便签是否已勾选；空库按未勾选处理。
    public func firstNoteIsDone() throws -> Bool {
        try firstNote()?.done ?? false
    }
}

/// SharedStore 专属错误。
public enum SharedStoreError: Error, Equatable, Sendable {
    /// App Group 容器不可用（宿主 target 缺少对应 entitlement 时发生）。
    case appGroupContainerUnavailable(String)
    /// note 主键不是合法 UUID 文本（正常写入路径不可能出现，防御性兜底）。
    case corruptNoteID(String)
}
