import Foundation
import Testing
import GRDB
import os
@testable import Core

/// W2-1 测试专用故障注入:模拟迁移竞态 / 瞬时打开失败(非 SQLITE_BUSY 类)。
private enum StoreTestFault: Error, Equatable {
    case simulatedMigrationRace
    case simulatedTransientOpenFailure
}

/// Task 3 / PoC B：App Group GRDB 双进程读写验证（D2「零丢数据」存储基础）。
/// 每个用例使用独立临时目录 + 独立连接，模拟 App / Widget 双进程隔离环境。
struct SharedStoreTests {

    /// 全新独立数据库路径（每次调用新临时目录，保证跨运行确定性）。
    private func makeDatabasePath() -> String {
        TestSupport.makeDatabasePath(prefix: "pocb")  // W2-3 Minor:共享 helper 去重
    }

    // MARK: - Step 3.1 跨连接可见性（独立连接 = 模拟 Widget 进程）

    @Test func crossProcessRead() async throws {
        let path = makeDatabasePath()
        let storeA = try SharedStore(databasePath: path)  // DatabasePool, WAL
        try await storeA.insert(Note(text: "hello"))

        let storeB = try SharedStore(databasePath: path)  // 独立连接 = 模拟 Widget 进程
        #expect(try storeB.countNotes() == 1)
    }

    // MARK: - 存储引擎配置断言（对原始 DB 状态断言，不经过写入方 accessor）

    @Test func journalModeIsWAL() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        // 用独立原始连接核对 journal mode（WAL 是数据库文件的持久属性）。
        let rawPool = try DatabasePool(path: path)
        let mode = try rawPool.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode?.lowercased() == "wal")
    }

    @Test func schemaNoteTableMatchesW2Columns() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        let columns = try rawPool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info('note')").map { row -> String in
                row["name"]
            }
        }
        // W2 schema：W1 四列之上 additive 增加 dueDate（可空）与 position（手动排序）。
        #expect(Set(columns) == ["id", "text", "createdAt", "done", "dueDate", "position"])
    }

    // MARK: - Step 3.4 并发写冲突：多条独立连接并发插入，零丢失

    @Test func concurrentInsertsFromIndependentConnectionsLoseNothing() async throws {
        let path = makeDatabasePath()
        let writers = try (0..<4).map { _ in try SharedStore(databasePath: path) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (writerIndex, store) in writers.enumerated() {
                group.addTask {
                    for noteIndex in 0..<25 {
                        try await store.insert(Note(text: "w\(writerIndex)-n\(noteIndex)"))
                    }
                }
            }
            try await group.waitForAll()
        }

        // 原始状态核对：新开独立连接清点，杜绝走写入方 accessor 的假阳性。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.countNotes() == 100)
    }

    /// 并发翻转的奇偶性断言：toggle 是「读-改-写」单事务，任何一次丢失更新
    /// 都会破坏偶数次翻转后回到 false 的不变量。
    @Test func concurrentTogglesFromIndependentConnectionsStayAtomic() async throws {
        let path = makeDatabasePath()
        let seed = try SharedStore(databasePath: path)
        try await seed.insert(Note(text: "唯一事项", done: false))

        let togglesPerConnection = 4
        let connections = try (0..<4).map { _ in try SharedStore(databasePath: path) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for store in connections {
                group.addTask {
                    for _ in 0..<togglesPerConnection {
                        _ = try await store.toggleFirstItem()
                    }
                }
            }
            try await group.waitForAll()
        }

        // 16 次（偶数）翻转后必须回到 false，且记录数不变、正文未被破坏。
        let fresh = try SharedStore(databasePath: path)
        let note = try fresh.firstNote()
        #expect(try fresh.countNotes() == 1)
        #expect(note?.done == false)
        #expect(note?.text == "唯一事项")
    }

    // MARK: - Step 3.5 模拟器级「50 连击零丢失」：单连接快速写 + 另一连接持续读

    @Test func fiftyRapidTogglesWithConcurrentReaderLoseNothing() async throws {
        let path = makeDatabasePath()
        let writer = try SharedStore(databasePath: path)
        let reader = try SharedStore(databasePath: path)
        try await writer.insert(Note(text: "50连击目标"))

        // 读连接在整个连击期间持续轮询（500 次足以覆盖写循环时长）：
        // 任何一次计数 != 1 或读取报错都算数据损坏/丢失。
        async let readerCounts: [Int] = {
            var counts: [Int] = []
            counts.reserveCapacity(500)
            for _ in 0..<500 {
                counts.append(try reader.countNotes())
                _ = try reader.firstNoteIsDone()
            }
            return counts
        }()

        for _ in 0..<50 {
            _ = try await writer.toggleFirstItem()
        }

        let counts = try await readerCounts
        #expect(counts.count == 500)
        #expect(counts.allSatisfy { $0 == 1 })

        // 终态用全新独立连接核对原始 DB：50 次偶数翻转 → false，正文完好。
        let fresh = try SharedStore(databasePath: path)
        let note = try fresh.firstNote()
        #expect(try fresh.countNotes() == 1)
        #expect(note?.text == "50连击目标")
        #expect(note?.done == false)
    }

    // MARK: - toggleFirstItem 语义（替代 ToggleItemIntentTests 的数据闭环验证）

    @Test func toggleFirstItemInsertsSeedWhenStoreEmpty() async throws {
        let store = try SharedStore(databasePath: makeDatabasePath())
        #expect(try store.countNotes() == 0)
        #expect(try store.firstNoteIsDone() == false)  // 空库按未勾选处理

        let firstFlip = try await store.toggleFirstItem()  // 空库 → 插入种子
        #expect(firstFlip == false)
        #expect(try store.countNotes() == 1)

        let secondFlip = try await store.toggleFirstItem()  // 有记录 → 翻转
        #expect(secondFlip == true)
        #expect(try store.firstNoteIsDone() == true)
    }

    @Test func toggleStateSurvivesFreshConnection() async throws {
        let path = makeDatabasePath()
        let writer = try SharedStore(databasePath: path)
        try await writer.insert(Note(text: "喂食"))
        _ = try await writer.toggleFirstItem()
        #expect(try writer.firstNoteIsDone() == true)

        // 原始状态核对：新开独立连接读取（模拟 Widget 进程重启后仍可见）。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.firstNoteIsDone() == true)
        _ = try await fresh.toggleFirstItem()
        #expect(try SharedStore(databasePath: path).firstNoteIsDone() == false)
    }

    // MARK: - App Group 路径解析

    @Test func appGroupDatabasePathPointsIntoAppGroupContainer() throws {
        // 宿主带 entitlement 时容器可用；本断言只校验路径格式，不强依赖模拟器 App Group 状态。
        guard let path = SharedStore.appGroupDatabasePath() else {
            Issue.record("App Group 容器不可用：\(PawItInfo.appGroupID)（宿主缺少 entitlement？）")
            return
        }
        #expect(path.hasSuffix("pawit.sqlite3"))
        #expect(path.contains("Application Support"))
        // 共享容器目录以 UUID 命名（不出现 group id 字面量），但固定位于 Shared/AppGroup 之下。
        #expect(path.contains("AppGroup"))
    }

    // MARK: - W2-1 评审项 1（+项 3）：进程级单池缓存（修 intent 每次开池 churn）

    @Test func cachedStoreOpensPoolOncePerProcess() throws {
        let path = makeDatabasePath()
        let creations = OSAllocatedUnfairLock(initialState: 0)
        let factory: @Sendable (String) throws -> SharedStore = { p in
            creations.withLock { $0 += 1 }
            return try SharedStore(databasePath: p)
        }

        let first = SharedStore.cachedStore(databasePath: path, factory: factory)
        let second = SharedStore.cachedStore(databasePath: path, factory: factory)

        #expect(first != nil)
        #expect(second != nil)
        #expect(creations.withLock { $0 } == 1)  // 第二次调用命中缓存，不再开池
    }

    /// 失败零缓存：瞬时失败后下次调用自动重试（评审项 3「不得永久缓存 nil」的同一规则）。
    @Test func cachedStoreCachesNothingOnFailureAndRetriesNextCall() throws {
        let path = makeDatabasePath()
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let flaky: @Sendable (String) throws -> SharedStore = { p in
            attempts.withLock { $0 += 1 }
            if attempts.withLock({ $0 }) == 1 {
                throw StoreTestFault.simulatedTransientOpenFailure
            }
            return try SharedStore(databasePath: p)
        }

        #expect(SharedStore.cachedStore(databasePath: path, factory: flaky) == nil)  // 首败 → nil
        #expect(SharedStore.cachedStore(databasePath: path, factory: flaky) != nil)  // 下次调用重试成功
        #expect(SharedStore.cachedStore(databasePath: path, factory: flaky) != nil)  // 成功后命中缓存
        #expect(attempts.withLock { $0 } == 2)  // 恰好两次真实创建：失败不入缓存，成功不重复创建
    }

    /// 并发冷启动 single-flight：并发调用方只允许一次真实开池。
    @Test func cachedStoreIsSingleFlightUnderConcurrency() async throws {
        let path = makeDatabasePath()
        let creations = OSAllocatedUnfairLock(initialState: 0)
        let factory: @Sendable (String) throws -> SharedStore = { p in
            creations.withLock { $0 += 1 }
            return try SharedStore(databasePath: p)
        }

        let results = try await withThrowingTaskGroup(of: SharedStore?.self) { group in
            for _ in 0..<16 {
                group.addTask { SharedStore.cachedStore(databasePath: path, factory: factory) }
            }
            var collected: [SharedStore?] = []
            for try await result in group { collected.append(result) }
            return collected
        }

        #expect(results.count == 16)
        #expect(results.allSatisfy { $0 != nil })
        #expect(creations.withLock { $0 } == 1)
    }

    // MARK: - W2-1 评审项 2：迁移竞态 retry-once（双进程冷启动撞表，非 BUSY）

    @Test func migratorFailureRetriesOnceOnFreshPoolThenWorks() async throws {
        let path = makeDatabasePath()
        let runs = OSAllocatedUnfairLock(initialState: 0)
        let runner: (DatabasePool, DatabaseMigrator) throws -> Void = { pool, migrator in
            runs.withLock { $0 += 1 }
            if runs.withLock({ $0 }) == 1 {
                throw StoreTestFault.simulatedMigrationRace  // 首尝试：另一进程抢先建表
            }
            try migrator.migrate(pool)
        }

        let store = try SharedStore(databasePath: path, migratorRunner: runner)

        #expect(runs.withLock { $0 } == 2)  // 恰好一次重试，非循环
        try await store.insert(Note(text: "竞态恢复后写入"))
        #expect(try store.countNotes() == 1)
    }

    @Test func migratorFailureThrowsAfterExactlyOneRetry() throws {
        let path = makeDatabasePath()
        let runs = OSAllocatedUnfairLock(initialState: 0)

        do {
            _ = try SharedStore(databasePath: path) { _, _ in
                runs.withLock { $0 += 1 }
                throw StoreTestFault.simulatedMigrationRace
            }
            Issue.record("两次迁移均失败时 init 必须抛错")
        } catch {
            #expect((error as? StoreTestFault) == .simulatedMigrationRace)
        }
        #expect(runs.withLock { $0 } == 2)  // 一次重试后放弃，不是无限循环
    }

    // MARK: - W2-1 评审项 4：DB + WAL 边车文件保护（锁屏 widget 首解前渲染）

    /// 注入式断言：三个候选文件（主库 / -wal / -shm）全部施加保护，值正确、顺序确定。
    /// 平台事实（本任务实测）：模拟器 setAttributes 成功但不持久化 protectionKey
    /// （attributesOfItem 读不回该键）——属性「值正确」由注入断言钉死；
    /// 真机才强制执行，「重启未解锁看锁屏」冒烟见《W1 架构备忘录》§6 待办。
    @Test func fileProtectionTargetsMainDBAndBothSidecars() {
        let candidates = [
            "/fake/pawit.sqlite3", "/fake/pawit.sqlite3-wal", "/fake/pawit.sqlite3-shm",
        ]
        let protectedPaths = OSAllocatedUnfairLock<[String]>(initialState: [])
        let applied = SharedStore.applyFileProtection(
            toFilesOf: "/fake/pawit.sqlite3",
            fileExists: { candidates.contains($0) },
            setProtection: { path in
                protectedPaths.withLock { $0.append(path) }
            }
        )
        #expect(applied == candidates)  // 主库与两个边车全部覆盖，不多不少
        #expect(protectedPaths.withLock { $0 } == candidates)  // 顺序：主库 → wal → shm
    }

    /// 边车首写才出现：尚不存在的 -wal/-shm 跳过（不报错、不误报）。
    @Test func fileProtectionSkipsSidecarsThatDoNotExistYet() {
        let applied = SharedStore.applyFileProtection(
            toFilesOf: "/fake/pawit.sqlite3",
            fileExists: { $0 == "/fake/pawit.sqlite3" },
            setProtection: { _ in }
        )
        #expect(applied == ["/fake/pawit.sqlite3"])
    }

    /// 真实文件路径：建库 + 写入后，生产默认实现（真 FileManager）对三个已落盘文件
    /// 全部发出保护调用（模拟器不持久化属性值，此处验证「调用了、没崩、覆盖全」）。
    @Test func fileProtectionCoversRealFilesAfterFirstWrite() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)  // init 内部即走生产默认实现
        try await store.insert(Note(text: "文件保护探针"))

        let applied = SharedStore.applyFileProtection(toFilesOf: path)  // 生产默认实现
        #expect(applied.count == 3)
        #expect(applied.contains(path))
        #expect(applied.contains(path + "-wal"))
        #expect(applied.contains(path + "-shm"))
        for file in applied {  // WAL 模式下连接打开 + 首写即创建边车，三个文件确实落盘
            #expect(FileManager.default.fileExists(atPath: file))
        }
    }

    // MARK: - W2-4 移交项⑩：对活库重设文件保护（大事务重建边车后的 hook）

    /// 实例级 reapplyFileProtection 必须覆盖本库自己的主库 + 两个边车——
    /// 导入（replace-all）等大事务会重写 -wal 边车，保护属性需补设（iOS）。
    @Test func reapplyFileProtectionCoversOwnLiveFiles() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        try await store.insert(Note(text: "保护重设探针"))

        let applied = store.reapplyFileProtection()
        #expect(applied.count == 3)
        #expect(applied.contains(path))
        #expect(applied.contains(path + "-wal"))
        #expect(applied.contains(path + "-shm"))
    }

    // MARK: - W2-1 评审项 5：首条排序 id 决胜

    @Test func firstNoteOrderingTiebreaksByIDWhenCreatedAtEqual() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let sameInstant = Date(timeIntervalSince1970: 1_000_000)
        let laterID = UUID(uuidString: "FFFF0000-0000-0000-0000-000000000002")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        // 先插 id 大者：无 id 决胜时 SQLite 按扫描序返回首插行（id 大）→ 断言失败（red）。
        try await store.insert(Note(id: laterID, text: "id 大，应排第二", createdAt: sameInstant))
        try await store.insert(Note(id: earlierID, text: "id 小，应排第一", createdAt: sameInstant))

        #expect(try store.firstNote()?.id == earlierID)

        // toggleFirstItem 与 firstNote 用同一排序，同样受 id 决胜约束。
        _ = try await store.toggleFirstItem()
        #expect(try store.firstNote()?.id == earlierID)
        #expect(try store.firstNote()?.done == true)
    }

    // MARK: - W2-3 移交项 ①：firstNote / toggleFirstItem 排序与 allNotes 统一（position 优先）

    /// 创建更早但 position 大 vs 创建更晚但 position 0：allNotes 以 position 决胜选后者，
    /// firstNote 必须给出同一条——否则 W3 拖拽排序上线后，widget 与编辑器的「第一条」分裂。
    @Test func firstNoteMatchesAllNotesFirstWhenPositionDiffers() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let early = Date(timeIntervalSince1970: 1_000_000)
        let noteA = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            text: "A 创建早 position 9", createdAt: early, position: 9
        )
        let noteB = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
            text: "B 创建晚 position 0", createdAt: early.addingTimeInterval(60), position: 0
        )
        try await store.upsertNote(noteA)
        try await store.upsertNote(noteB)

        let fresh = try SharedStore(databasePath: path)
        let allNotesFirst = try #require(try fresh.allNotes().first)
        #expect(allNotesFirst.id == noteB.id)  // 基线：allNotes 由 position 决胜 → B
        #expect(try fresh.firstNote()?.id == allNotesFirst.id)  // red：旧实现按 createdAt 选 A
    }

    /// toggleFirstItem 与 firstNote 同一排序契约：翻的必须是 position 靠前的便签。
    @Test func toggleFirstItemFlipsUnifiedOrderingFirstNote() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let early = Date(timeIntervalSince1970: 1_000_000)
        let noteA = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            text: "A 创建早 position 9", createdAt: early, position: 9
        )
        let noteB = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
            text: "B 创建晚 position 0", createdAt: early.addingTimeInterval(60), position: 0
        )
        try await store.upsertNote(noteA)
        try await store.upsertNote(noteB)

        let flipped = try await store.toggleFirstItem()
        #expect(flipped == true)

        // 原始状态核对：翻的是 position 0 的 B（red：旧实现翻 createdAt 更早的 A），A 不被牵连。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.firstNote()?.id == noteB.id)
        #expect(try fresh.firstNote()?.done == true)
        let noteAAfter = try #require(try fresh.allNotes().first { $0.id == noteA.id })
        #expect(noteAAfter.done == false)
    }
}
