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

    /// 全量迁移：w1.v1 → w2.v1。迁移是 append-only 的——已发布迁移体一经上线即冻结
    /// （改动它 = 已装机走旧体、新装机走新体，语义漂移且难排查），演进 schema 只能
    /// 追加新迁移，这正是选 GRDB 规避 SwiftData 类「schema hash brick」失败的纪律。
    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerW1V1(on: &migrator)
        registerW2V1(on: &migrator)
        return migrator
    }

    /// W1 最小迁移（冻结，永不修改）：note(id TEXT PK, text, createdAt, done)。
    /// internal 是给迁移测试的注入缝：测试用它造「只跑到 w1 的存量库」再走真实升级路径。
    static func registerW1V1(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("w1.v1") { db in
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
            }
        }
    }

    /// W2-2 迁移（additive）：note 增列 + 三张新表。日期编码决策：全部走 GRDB
    /// `.datetime` 列——GRDB 默认把 Date 持久化为 "YYYY-MM-DD HH:MM:SS.SSS" 文本，
    /// 与 w1 的 `createdAt` 同族（选 TEXT 家族而非 DOUBLE epoch：库内日期编码单一，
    /// 人读可辨，GRDB 双向转换零配置；毫秒精度足够便签/提醒场景）。
    /// 外键：GRDB `Configuration.foreignKeysEnabled` 默认 true（连接级 PRAGMA），
    /// 级联行为由 SchemaTests/deleteNoteCascadesItemsAcrossConnections 行为级钉死。
    static func registerW2V1(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("w2.v1") { db in
            // ① note 增列：dueDate 可空（nil = 未设到期）；position 手动排序，存量行补 0。
            try db.alter(table: "note") { t in
                t.add(column: "dueDate", .datetime)
                t.add(column: "position", .integer).notNull().defaults(to: 0)
            }
            // ② 清单项：挂在便签之下，删便签级联清空。
            try db.create(table: "note_item") { t in
                t.column("id", .text).primaryKey()
                t.column("noteId", .text).notNull().references("note", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            // noteItems(noteId:) 查询与级联删除都走 noteId，建索引免全表扫描。
            try db.create(indexOn: "note_item", columns: ["noteId"])
            // ③ 宠物档案：首发六宠（species 见 PetSpecies）。
            try db.create(table: "pet_profile") { t in
                t.column("id", .text).primaryKey()
                t.column("species", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("isSelected", .boolean).notNull().defaults(to: false)
                t.column("acquiredAt", .datetime).notNull()
            }
            // ④ 轻养成状态：纯存储骨架（逻辑归 W2-3/W7）。unlockedOutfits 存 JSON 数组原文。
            try db.create(table: "growth_state") { t in
                t.column("petId", .text).primaryKey().references("pet_profile", onDelete: .cascade)
                t.column("fedLevel", .integer).notNull().defaults(to: 0)
                t.column("streakDays", .integer).notNull().defaults(to: 0)
                t.column("lastActiveDay", .datetime)
                t.column("unlockedOutfits", .text).notNull().defaults(to: "[]")
            }
        }
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

    // MARK: - W2-2 最小持久化 API（写入 async，读取同步；引擎语义归 W2-3，仓库层归 W2-4）

    // —— Note ——

    /// 插入或更新便签（按主键 upsert：存在则更新，不存在则插入）。
    public func upsertNote(_ note: Note) async throws {
        try await pool.write { db in
            try note.save(db)
        }
    }

    /// 全部便签，排序 (position ASC, createdAt ASC, id ASC)：
    /// position 是手动排序键；同 position 时保留 w1 的 createdAt → id 决胜
    /// （与 `firstNote()` 同族规则，排序确定性是 W2-1 评审项 5 的延续）。
    public func allNotes() throws -> [Note] {
        try pool.read { db in
            try Note
                .order(Column("position").asc, Column("createdAt").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    /// 删除便签；其清单项经外键 `ON DELETE CASCADE` 连带清空（同事务内数据库侧完成）。
    public func deleteNote(id: UUID) async throws {
        try await pool.write { db in
            _ = try Note.deleteOne(db, key: id.uuidString)
        }
    }

    // —— NoteItem ——

    /// 新增清单项。
    public func addNoteItem(_ item: NoteItem) async throws {
        try await pool.write { db in
            try item.insert(db)
        }
    }

    /// 翻转指定清单项的 done 标记，返回翻转后的状态。
    /// 读-改-写在同一写事务内原子完成（与 `toggleFirstItem()` 同一模式）；
    /// WHERE 同时钉死 noteId 与 itemId——跨便签的 item 翻不到（作用域错配抛错零副作用）。
    /// - Throws: `SharedStoreError.noteItemNotFound`（item 不存在或不属于该 note）。
    @discardableResult
    public func toggleNoteItem(noteId: UUID, itemId: UUID) async throws -> Bool {
        try await pool.write { db in
            guard var item = try NoteItem
                .filter(Column("id") == itemId.uuidString)
                .filter(Column("noteId") == noteId.uuidString)
                .fetchOne(db)
            else {
                throw SharedStoreError.noteItemNotFound(noteId: noteId, itemId: itemId)
            }
            item.done.toggle()
            try item.update(db)
            return item.done
        }
    }

    /// 指定便签的清单项，排序 (position ASC, id ASC)——position 同值以 id 决胜。
    public func noteItems(noteId: UUID) throws -> [NoteItem] {
        try pool.read { db in
            try NoteItem
                .filter(Column("noteId") == noteId.uuidString)
                .order(Column("position").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    // —— PetProfile / GrowthState ——

    /// 插入或更新宠物档案（按主键 upsert）。多选中的「互斥去选」是引擎语义（W2-3/W6），本层不代劳。
    public func upsertPet(_ pet: PetProfile) async throws {
        try await pool.write { db in
            try pet.save(db)
        }
    }

    /// 当前选中的宠物；若脏数据出现多行 isSelected，以 id ASC 决胜保证读侧确定性。
    public func selectedPet() throws -> PetProfile? {
        try pool.read { db in
            try PetProfile
                .filter(Column("isSelected") == true)
                .order(Column("id").asc)
                .fetchOne(db)
        }
    }

    /// 插入或更新养成状态（按主键 upsert；纯存储，逻辑归 W2-3/W7）。
    public func upsertGrowthState(_ state: GrowthState) async throws {
        try await pool.write { db in
            try state.save(db)
        }
    }

    /// 指定宠物的养成状态；无记录返回 nil（不代建，首只宠物的初值由调用方写入）。
    public func growthState(petId: String) throws -> GrowthState? {
        try pool.read { db in
            try GrowthState.filter(Column("petId") == petId).fetchOne(db)
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
    /// 主键列不是合法 UUID 文本（正常写入路径不可能出现，防御性兜底）。
    case corruptNoteID(String)
    /// pet_profile.species 不是首发六宠的合法 rawValue（脏数据/未知版本写入，防御性兜底）。
    case corruptPetSpecies(String)
    /// toggleNoteItem 的作用域错配：itemId 不存在，或不属于给定 noteId。
    case noteItemNotFound(noteId: UUID, itemId: UUID)
}
