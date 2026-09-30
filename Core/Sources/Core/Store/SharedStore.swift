import Foundation
import GRDB
import os

/// App Group 容器内的跨进程共享存储（Task 3 / PoC B，D2「零丢数据」的落地点）。
///
/// - GRDB `DatabasePool`：自动启用 WAL 日志（单写多读），App / Widget 扩展两个进程
///   各持独立连接并发访问同一数据库文件；`DatabasePool` 本身 Sendable。
/// - `busyTimeout = 2s`：跨进程写冲突时挂起等待而非上抛 `SQLITE_BUSY`。
/// - 读取走同步 `read`（WAL 读不阻塞写，供 Widget 渲染等同步路径直接调用）；
///   写入走 `async write`（协作线程池，不阻塞调用方执行器）。
public struct SharedStore: Sendable {
    private let pool: DatabasePool

    // MARK: - 进程级单池缓存（W2-1 评审项 1 / 3）

    /// 进程级缓存：路径 → 已打开的库。
    /// 选型说明：`OSAllocatedUnfairLock` 本身 `Sendable`，状态必须 `Sendable`
    /// （`SharedStore` 是 Sendable struct）——无需 `@unchecked Sendable` 或
    /// `nonisolated(unsafe)`；冷启动 single-flight（锁内创建，杜绝并发重复开池），
    /// 命中路径只是一次字典查询，渲染/tap 热路径零开销。
    private static let cache = OSAllocatedUnfairLock<[String: SharedStore]>(initialState: [:])

    /// 进程级复用的共享库访问点（W2-1 评审项 1）：每进程懒加载开池一次，
    /// 供 ToggleItemIntent（每次 tap）与 Widget 渲染复用同一 DatabasePool。
    /// 失败零缓存（W2-1 评审项 3）：返回 nil 时不缓存任何状态，下次调用自动重试——
    /// 瞬时故障（容器暂不可用等）自愈，永久故障（缺 entitlement）每次 cheap 失败。
    public static func cachedAppGroup() -> SharedStore? {
        guard let path = appGroupDatabasePath() else { return nil }
        return cachedStore(databasePath: path)
    }

    /// 按路径的进程级缓存访问（internal：测试可注入临时路径与工厂）。
    /// 锁内创建（single-flight）：并发冷启动也只允许一次真实开池；
    /// 失败（`factory` 抛错）不入缓存，直接返回 nil——下次调用自动重试。
    static func cachedStore(
        databasePath path: String,
        factory: @Sendable (String) throws -> SharedStore = { try SharedStore(databasePath: $0) }
    ) -> SharedStore? {
        cache.withLock { cached in
            if let hit = cached[path] { return hit }
            guard let store = try? factory(path) else { return nil }
            cached[path] = store
            return store
        }
    }

    /// 在指定路径打开（必要时创建）共享数据库；目录不存在时自动创建，首次运行自动建表。
    /// - Parameters:
    ///   - migratorRunner: 迁移执行器（W2-1 评审项 2 可注入点，默认即 GRDB migrate）。
    public init(
        databasePath: String,
        migratorRunner: (DatabasePool, DatabaseMigrator) throws -> Void = { try $1.migrate($0) }
    ) throws {
        let fileURL = URL(fileURLWithPath: databasePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        // 双进程写冲突容忍窗口：最多等 2s，超时才上抛 SQLITE_BUSY（GRDB 7 的 busyMode API）。
        configuration.busyMode = .timeout(2)
        let migrator = Self.makeMigrator()

        // 迁移竞态兜底（W2-1 评审项 2）：双进程冷启动同时跑 migrator，落败方拿到
        // "table already exists"（非 SQLITE_BUSY，busyTimeout 帮不上）。处理：
        // 关闭失败连接（弃用可能残留的损坏事务状态）→ 全新开池 → 再跑一次 migrator
        // （胜出方已完成的迁移会被 GRDB 的迁移记录跳过，此处即成功）。仅一次重试，
        // 再失败则上抛——不掩盖真实故障。
        let firstPool = try DatabasePool(path: databasePath, configuration: configuration)
        do {
            try migratorRunner(firstPool, migrator)
            self.pool = firstPool
        } catch {
            try? firstPool.close()
            let retryPool = try DatabasePool(path: databasePath, configuration: configuration)
            do {
                try migratorRunner(retryPool, migrator)
                self.pool = retryPool
            } catch {
                try? retryPool.close()
                throw error
            }
        }

        // 文件保护（W2-1 评审项 4）：锁屏 Widget 在用户首解锁前就要渲染，库文件或
        // WAL 边车若处于（或回落到）比 `.completeUntilFirstUserAuthentication` 更严的
        // 保护级别、或主库与边车级别不一致，首解前的读取会撞 SQLITE_IOERR——
        // 这是 App Group 容器 WAL 场景的经典坑。迁移本身即首次写入，-wal/-shm 此时
        // 已落盘，故对已存在的文件统一补设属性（不存在者跳过）；模拟器不持久化
        // 该属性（setAttributes 成功但读不回），真机「重启未解锁看锁屏」冒烟
        // 见《W1 架构备忘录》§6。
        #if os(iOS)
        Self.applyFileProtection(toFilesOf: databasePath)
        #endif
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
    /// Widget / Intent 等每次调用都开新池的场景请改用 `cachedAppGroup()`（W2-1 评审项 1）。
    public static func appGroup() throws -> SharedStore {
        guard let path = appGroupDatabasePath() else {
            throw SharedStoreError.appGroupContainerUnavailable(PawItInfo.appGroupID)
        }
        return try SharedStore(databasePath: path)
    }

    /// 文件保护硬化（W2-1 评审项 4）：主库 + WAL 边车统一
    /// `.completeUntilFirstUserAuthentication`。best-effort：个别文件设置失败
    /// 不阻塞存储可用性（保护是纵深防御，不是功能开关）。
    /// - Parameters:
    ///   - fileExists / setProtection: 注入点（默认真 FileManager），供测试钉死
    ///     「哪些文件、什么值」——模拟器不持久化 protectionKey（setAttributes 成功
    ///     但 attributesOfItem 读不回），真机才强制执行。
    /// - Returns: 实际尝试施加保护的文件路径（存在者），顺序：主库 → wal → shm。
    /// - Note: 文件保护是 iOS 概念（watchOS 无此 API），调用点带 `#if os(iOS)`；
    ///   真机「重启未解锁看锁屏」冒烟见《W1 架构备忘录》§6 待办。
    #if os(iOS)
    @discardableResult
    static func applyFileProtection(
        toFilesOf databasePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        setProtection: (String) throws -> Void = { path in
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: path
            )
        }
    ) -> [String] {
        var applied: [String] = []
        let candidates = [databasePath, databasePath + "-wal", databasePath + "-shm"]
        for path in candidates where fileExists(path) {
            try? setProtection(path)
            applied.append(path)
        }
        return applied
    }
    #endif

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
    /// 排序同 `firstNote()`：createdAt 同值时以 id ASC 决胜（W2-1 评审项 5），
    /// 避免 SQLite 同值扫描序随机化导致「第一条」漂移。
    /// - Returns: 本次操作后的 done 状态。
    @discardableResult
    public func toggleFirstItem() async throws -> Bool {
        try await pool.write { db in
            if var note = try Note.order(Column("createdAt").asc, Column("id").asc).fetchOne(db) {
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

    /// 「第一条」便签（createdAt 最早；同值以 id ASC 决胜，W2-1 评审项 5——
    /// createdAt 为毫秒/微秒级时间戳，同刻插入的两条必须有确定性的稳定顺序）。
    public func firstNote() throws -> Note? {
        try pool.read { db in
            try Note.order(Column("createdAt").asc, Column("id").asc).fetchOne(db)
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
