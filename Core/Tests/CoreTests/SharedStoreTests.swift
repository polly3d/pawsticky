import Foundation
import Testing
import GRDB
@testable import Core

/// Task 3 / PoC B：App Group GRDB 双进程读写验证（D2「零丢数据」存储基础）。
/// 每个用例使用独立临时目录 + 独立连接，模拟 App / Widget 双进程隔离环境。
struct SharedStoreTests {

    /// 全新独立数据库路径（每次调用新临时目录，保证跨运行确定性）。
    private func makeDatabasePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawit-pocb-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("pawit.sqlite3").path
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

    @Test func schemaIsMinimalNoteTable() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        let columns = try rawPool.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info('note')").map { row -> String in
                row["name"]
            }
        }
        // W1 最小 schema：note(id TEXT PK, text, createdAt, done)，真实 schema 由 W2 设计。
        #expect(Set(columns) == ["id", "text", "createdAt", "done"])
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
}
