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

    /// 存储诊断日志（W2-4 移交项⑨）：初始化失败/容器不可用不再静默。
    static let storeLogger = Logger(subsystem: "com.pawit.app", category: "store")

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
    /// W2-4 移交项⑨：失败路径经 os_log（subsystem com.pawit.app / category store）
    /// 输出诊断，不再静默——容器不可用记 error，开池异常记 fault（含底层错误描述）。
    public static func cachedAppGroup() -> SharedStore? {
        guard let path = appGroupDatabasePath() else {
            storeLogger.error(
                "cachedAppGroup: App Group 容器不可用 (\(PawItInfo.appGroupID, privacy: .public))"
            )
            return nil
        }
        return cachedStore(databasePath: path)
    }

    /// 按路径的进程级缓存访问（internal：测试可注入临时路径与工厂）。
    /// 锁内创建（single-flight）：并发冷启动也只允许一次真实开池；
    /// 失败（`factory` 抛错）不入缓存，直接返回 nil——下次调用自动重试（⑨：异常经 os_log 输出）。
    static func cachedStore(
        databasePath path: String,
        factory: @Sendable (String) throws -> SharedStore = { try SharedStore(databasePath: $0) }
    ) -> SharedStore? {
        cache.withLock { cached in
            if let hit = cached[path] { return hit }
            do {
                let store = try factory(path)
                cached[path] = store
                return store
            } catch {
                storeLogger.fault(
                    "cachedStore: 数据库开池失败 (\(path, privacy: .public)): \(String(describing: error), privacy: .public)"
                )
                return nil
            }
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

    /// W2-4 移交项⑩（自 W2-1 遗留）：对**本库当前**的主库 + WAL/-shm 边车重新施加
    /// 文件保护。必要性：导入（replace-all）等大批量写事务会重写/重建 `-wal` 边车
    /// （checkpoint 后截断、或长事务换新文件），新边车不继承保护属性——主库与边车
    /// 级别不一致正是锁屏首解前 SQLITE_IOERR 的经典来源。调用点：`NoteRepository.import`
    /// 完成后；其余大事务如有需要同理补调（best-effort，见 `applyFileProtection`）。
    @discardableResult
    public func reapplyFileProtection() -> [String] {
        Self.applyFileProtection(toFilesOf: pool.path)
    }
    #endif

    // MARK: - Schema

    /// 全量迁移：w1.v1 → w2.v1 → w2.v2。迁移是 append-only 的——已发布迁移体一经上线即冻结
    /// （改动它 = 已装机走旧体、新装机走新体，语义漂移且难排查），演进 schema 只能
    /// 追加新迁移，这正是选 GRDB 规避 SwiftData 类「schema hash brick」失败的纪律。
    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerW1V1(on: &migrator)
        registerW2V1(on: &migrator)
        registerW2V2(on: &migrator)
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

    /// W2-4 迁移（additive）：history_log 回滚日志表。
    ///
    /// **Append-only 写入纪律**（本表的正确性契约，写入方为 `HistoryLog`）：
    /// 本表只有两种写——`INSERT`（每次实体变更落一条整行快照）与 `DELETE`
    /// （仅限保留期清理：`changedAt` 早于 7 天前的条目，由每次 append 顺手执行）。
    /// **永不 UPDATE**：条目一经落盘不可变，否则「回滚依据」本身可被篡改，
    /// 审计链断言失效。保留期清理是 retention（数据治理），不是对记录的修订。
    ///
    /// - `entityId` 一律 TEXT：便签/清单项存 `uuidString`，宠物/养成状态存其 String id。
    /// - `payload` 为整行快照的 JSON 字符串（编码走导出 DTO，单一编码路径，见 `ExportFormat`）。
    /// - `changedAt` 与其余日期列同族：GRDB `.datetime` 文本编码，字典序 == 时间序。
    /// - 索引 (entityType, entityId)：`history(for:)` 按实体取数是唯一查询模式。
    static func registerW2V2(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("w2.v2") { db in
            try db.create(table: "history_log") { t in
                t.column("id", .text).primaryKey()
                t.column("entityType", .text).notNull()
                t.column("entityId", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("changedAt", .datetime).notNull()
            }
            try db.create(indexOn: "history_log", columns: ["entityType", "entityId"])
        }
    }

    // MARK: - 写入（async，协作式）

    /// 插入一条便签。不落历史;App 内变更请走 NoteRepository。
    public func insert(_ note: Note) async throws {
        try await pool.write { db in
            try note.insert(db)
        }
    }

    /// 翻转「第一条」便签的 done 标记；库里为空则先插入一条种子便签（done=false）。
    /// 读-改-写在同一写事务内原子完成，跨连接并发调用不丢失更新。
    /// 排序与 `allNotes()`/`firstNote()` 完全同族：(position, createdAt, id) ASC
    /// （W2-3 移交项 ①：补上 position，防 W3 拖拽排序后 widget 与编辑器的「第一条」分裂；
    /// createdAt 同值时以 id ASC 决胜是 W2-1 评审项 5 的延续——避免 SQLite 同值扫描序
    /// 随机化导致「第一条」漂移。存量 w1 行 position 全 0，行为不变）。
    /// - Returns: 本次操作后的 done 状态。
    /// 不落历史;App 内变更请走 NoteRepository(Widget intent 直写是 W5 的已登记迁移项)。
    @discardableResult
    public func toggleFirstItem() async throws -> Bool {
        try await pool.write { db in
            if var note = try Note
                .order(Column("position").asc, Column("createdAt").asc, Column("id").asc)
                .fetchOne(db) {
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

    /// 原子翻转指定便签的 done 标记（W3-0① per-note toggle）。
    /// 读-改-写在同一写事务内原子完成（与 `toggleFirstItem()` 同一模式）。
    /// - Throws: `SharedStoreError.noteNotFound` 目标便签不存在。
    /// - Returns: 翻转后的 done 状态。
    /// 不落历史;App 内变更请走 NoteRepository（其 toggleNote 在同一事务内补前像）。
    @discardableResult
    public func toggleNote(id: UUID) async throws -> Bool {
        try await pool.write { db in
            guard var note = try Note.fetchOne(db, key: id.uuidString) else {
                throw SharedStoreError.noteNotFound(id)
            }
            note.done.toggle()
            try note.update(db)
            return note.done
        }
    }

    /// 插入或更新便签（按主键 upsert：存在则更新，不存在则插入）。
    ///
    /// **整行覆盖契约（W2-4 移交项⑥）**：`save` 对已存在的行执行整行 UPDATE——
    /// 冲突时以**传入值的全部列为准**（text/createdAt/done/dueDate/position 一律覆盖，
    /// 不会保留库内旧值）。因此调用方必须携带完整读回的对象（先 `allNotes()`/
    /// `firstNote()` 读出、修改目标列后再 upsert），直接拿凭空构造的同 id 对象调用
    /// 会把其余列打回传入值。需要「读-改-写必须基于库内现值」的语义时请用
    /// `NoteRepository.updateNote`（行不存在抛错、且落历史前像）。
    /// 不落历史;App 内变更请走 NoteRepository。
    public func upsertNote(_ note: Note) async throws {
        try await pool.write { db in
            try note.save(db)
        }
    }

    /// 全部便签，排序 (position ASC, createdAt ASC, id ASC)。
    /// 这是便签排序的**权威定义**（store 是 SQL 排序的单一事实源）：
    /// position 是手动排序键；同 position 时保留 w1 的 createdAt → id 决胜
    /// （排序确定性是 W2-1 评审项 5 的延续）。
    /// `firstNote()`/`toggleFirstItem()` 与 `NoteEngine.sortedNotes(_:)` 同族同序
    /// （W2-3 移交项 ①：三处统一，防 W3 拖拽排序后 widget 与编辑器「第一条」分裂）。
    public func allNotes() throws -> [Note] {
        try pool.read { db in
            try Note
                .order(Column("position").asc, Column("createdAt").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    /// 按到期日排序的全部便签（W2-3 移交项 ②）：(dueDate IS NULL, dueDate ASC,
    /// position ASC, id ASC)。
    /// **nil-last 决策**：SQLite 中 `dueDate IS NULL` 对非 NULL 行取 0、对 NULL 行取 1，
    /// 升序时 0 在 1 前——即有日期者按时间升序打头、未设到期者殿后。（裸
    /// `ORDER BY dueDate ASC` 会把 NULL 排在最前，与「先看什么时候到期」的直觉相反。）
    /// W2-3 评审修正（措辞收敛）：本序与 `allNotes()` 的 (position, createdAt, id) **前缀
    /// 规则相近但非同族**——本查询无 createdAt 决胜列（到期场景下 dueDate 已区分
    /// 先后，position 是次级锚点）；「同族」仅指同以 (position, id) 做末级决胜。
    /// 引擎侧的到期语义（today/overdue 判定）见 `NoteEngine.dueStatus`。
    public func notesOrderedByDueDate() throws -> [Note] {
        try pool.read { db in
            try Note
                .order(sql: "dueDate IS NULL, dueDate ASC, position ASC, id ASC")
                .fetchAll(db)
        }
    }

    /// 删除便签；其清单项经外键 `ON DELETE CASCADE` 连带清空（同事务内数据库侧完成）。
    /// 不落历史;App 内变更请走 NoteRepository。
    public func deleteNote(id: UUID) async throws {
        try await pool.write { db in
            _ = try Note.deleteOne(db, key: id.uuidString)
        }
    }

    // —— NoteItem ——

    /// 新增清单项。不落历史;App 内变更请走 NoteRepository。
    public func addNoteItem(_ item: NoteItem) async throws {
        try await pool.write { db in
            try item.insert(db)
        }
    }

    /// 更新清单项（整行覆盖;必须存在,不做静默插入）。
    /// 不落历史;App 内变更请走 NoteRepository（其 updateItem 在同一事务内补前像）。
    /// - Throws: `SharedStoreError.noteItemNotFound`（item 不存在或不属于该 note）。
    public func updateNoteItem(_ item: NoteItem) async throws {
        try await pool.write { db in
            guard try NoteItem
                .filter(Column("id") == item.id.uuidString)
                .filter(Column("noteId") == item.noteId.uuidString)
                .fetchOne(db) != nil
            else {
                throw SharedStoreError.noteItemNotFound(noteId: item.noteId, itemId: item.id)
            }
            try item.update(db)
        }
    }

    /// 翻转指定清单项的 done 标记，返回翻转后的状态。
    /// 读-改-写在同一写事务内原子完成（与 `toggleFirstItem()` 同一模式）；
    /// WHERE 同时钉死 noteId 与 itemId——跨便签的 item 翻不到（作用域错配抛错零副作用）。
    /// - Throws: `SharedStoreError.noteItemNotFound`（item 不存在或不属于该 note）。
    /// 不落历史;App 内变更请走 NoteRepository(其 toggleItem 在同一事务内补前像)。
    @discardableResult
    public func toggleNoteItem(noteId: UUID, itemId: UUID) async throws -> Bool {
        try await pool.write { db in
            try Self.toggleNoteItem(db: db, noteId: noteId, itemId: itemId)
        }
    }

    /// toggleNoteItem 的事务本体（W2-4 重构）：public API 与 NoteRepository 共用——
    /// 仓库在自身事务作用域内调用本函数，保证「原子读-改-写 + 历史快照」同一事务。
    @discardableResult
    static func toggleNoteItem(db: Database, noteId: UUID, itemId: UUID) throws -> Bool {
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
    /// 不落历史;App 内变更请走 NoteRepository。
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
    /// 不落历史;App 内变更请走 NoteRepository。
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

    /// 「第一条」便签，排序与 `allNotes()` 统一：(position, createdAt, id) ASC
    /// （W2-3 移交项 ①：补上 position 列——W3 拖拽排序后 widget 的「第一条」
    /// 必须与编辑器列表首位一致；存量 w1 行 position 全 0，行为不变。
    /// createdAt 同值以 id ASC 决胜是 W2-1 评审项 5——同刻插入的两条必须有
    /// 确定性的稳定顺序）。
    public func firstNote() throws -> Note? {
        try pool.read { db in
            try Note
                .order(Column("position").asc, Column("createdAt").asc, Column("id").asc)
                .fetchOne(db)
        }
    }

    /// 「第一条」便签是否已勾选；空库按未勾选处理。
    public func firstNoteIsDone() throws -> Bool {
        try firstNote()?.done ?? false
    }

    // MARK: - 事务作用域（W2-4：NoteRepository 原子性契约的使能点；internal）

    /// 写事务作用域：块内全部语句同事务提交/回滚。NoteRepository 用它把
    /// 「实体变更 + HistoryLog 快照」绑定为不可分割单元（历史与变更同生共死）。
    func write<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await pool.write(body)
    }

    /// 读作用域（WAL 读不阻塞写）。
    func read<T: Sendable>(_ body: @Sendable (Database) throws -> T) throws -> T {
        try pool.read(body)
    }
}

/// SharedStore 专属错误。
public enum SharedStoreError: Error, Equatable, Sendable {
    /// App Group 容器不可用（宿主 target 缺少对应 entitlement 时发生）。
    case appGroupContainerUnavailable(String)
    /// 存储中的 UUID 文本列损坏（正常写入路径不可能出现，防御性兜底）。
    /// W2-4 移交项⑧文档修正：**不限主键**——Note.id、NoteItem.id、NoteItem.noteId
    /// 均经 `UUID.parseStorage` 解析并复用本错误（命名沿用 w1 冻结值，语义即
    /// 「应为 UUID 的 TEXT 列损坏」）。
    case corruptNoteID(String)
    /// pet_profile.species 不是首发六宠的合法 rawValue（脏数据/未知版本写入，防御性兜底）。
    case corruptPetSpecies(String)
    /// history_log.entityType 不是合法的 HistoryEntityType rawValue（W2-4 新增，防御性兜底）。
    case corruptHistoryEntityType(String)
    /// toggleNoteItem 的作用域错配：itemId 不存在，或不属于给定 noteId。
    case noteItemNotFound(noteId: UUID, itemId: UUID)
    /// toggleNote(id:) 的目标便签不存在（W3-0 新增）。
    case noteNotFound(UUID)
}
