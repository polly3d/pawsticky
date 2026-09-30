import Foundation
import Testing
import GRDB
@testable import Core

/// W2-2:w2.v1 迁移钉子——迁移只增不改（w1.v1 冻结）、四表列集精确钉死（防范围蠕动）、
/// 外键与级联删除行为可证。日期编码决策:全部走 GRDB `.datetime` 列（与 w1 的
/// `createdAt` 同族,GRDB 默认把 Date 持久化为 "YYYY-MM-DD HH:MM:SS.SSS" 文本）。
struct SchemaTests {

    /// 全新独立数据库路径（每次调用新临时目录,保证跨运行确定性）。
    private func makeDatabasePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawit-w22-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("pawit.sqlite3").path
    }

    /// 造一个「只跑到 w1.v1」的旧版数据库:复用生产迁移注册（单一事实源）,
    /// 模拟 W1 用户的存量库,再交由 SharedStore 全量迁移——真实升级路径。
    /// 裸 DatabasePool 不建中间目录（生产路径由 SharedStore.init 代建）,这里补上。
    private func makeW1OnlyDatabase(at path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let pool = try DatabasePool(path: path)
        var migrator = DatabaseMigrator()
        SharedStore.registerW1V1(on: &migrator)
        try migrator.migrate(pool)
    }

    // MARK: - w1 → w2 增量迁移:数据保全 + 列默认值

    @Test func w1DatabaseMigratesToW2PreservingData() throws {
        let path = makeDatabasePath()
        try makeW1OnlyDatabase(at: path)

        // W1 存量数据:用 w1 时代的列写入（当时不存在 dueDate/position）。
        let w1NoteID = UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!
        let w1CreatedAt = Date(timeIntervalSince1970: 1_000_000)
        try DatabasePool(path: path).write { db in
            try db.execute(
                sql: "INSERT INTO note (id, text, createdAt, done) VALUES (?, ?, ?, ?)",
                arguments: [w1NoteID.uuidString, "W1 存量便签", w1CreatedAt, true]
            )
        }

        // 用当前 SharedStore 打开:w1.v1 已应用（跳过）,w2.v1 增量执行,数据保全。
        let store = try SharedStore(databasePath: path)
        let notes = try store.allNotes()

        #expect(notes.count == 1)
        #expect(notes[0].id == w1NoteID)
        #expect(notes[0].text == "W1 存量便签")
        #expect(notes[0].done == true)
        #expect(notes[0].createdAt == w1CreatedAt)
        // 新列按迁移默认值落位:存量行为 position 0、无到期日。
        #expect(notes[0].position == 0)
        #expect(notes[0].dueDate == nil)

        // 迁移记录精确为两步、顺序正确（w2.v1 是 w1.v1 之后唯一新增迁移）。
        let migrations = try DatabasePool(path: path).read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
        #expect(migrations == ["w1.v1", "w2.v1"])
    }

    // MARK: - PRAGMA table_info:四表列集精确钉死

    @Test func pragmaTableInfoPinsExactColumnsOfAllFourTables() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        func columnNames(_ table: String) throws -> Set<String> {
            try rawPool.read { db in
                Set(try Row.fetchAll(db, sql: "PRAGMA table_info('\(table)')").map { row -> String in
                    row["name"]
                })
            }
        }

        #expect(try columnNames("note") == ["id", "text", "createdAt", "done", "dueDate", "position"])
        #expect(try columnNames("note_item") == ["id", "noteId", "text", "done", "position", "createdAt"])
        #expect(try columnNames("pet_profile") == ["id", "species", "displayName", "isSelected", "acquiredAt"])
        #expect(try columnNames("growth_state") == ["petId", "fedLevel", "streakDays", "lastActiveDay", "unlockedOutfits"])
    }

    // MARK: - 外键:GRDB 默认开启（Configuration.foreignKeysEnabled = true）,
    // 行为级证明见 deleteNoteCascadesItemsAcrossConnections。

    @Test func foreignKeysPragmaEnabledOnDefaultConnections() throws {
        let path = makeDatabasePath()
        _ = try SharedStore(databasePath: path)

        let rawPool = try DatabasePool(path: path)
        let enabled = try rawPool.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        #expect(enabled == 1)
    }

    // MARK: - 级联删除:deleteNote 连带清空其清单项（外键在该连接上生效的行为证明）

    @Test func deleteNoteCascadesItemsAcrossConnections() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let noteN = Note(id: UUID(), text: "被删便签", createdAt: Date(timeIntervalSince1970: 1))
        let noteM = Note(id: UUID(), text: "存活便签", createdAt: Date(timeIntervalSince1970: 2))
        try await store.upsertNote(noteN)
        try await store.upsertNote(noteM)
        try await store.addNoteItem(NoteItem(noteId: noteN.id, text: "N-事项1"))
        try await store.addNoteItem(NoteItem(noteId: noteN.id, text: "N-事项2"))
        try await store.addNoteItem(NoteItem(noteId: noteM.id, text: "M-事项1"))

        try await store.deleteNote(id: noteN.id)

        // 全新独立连接核对原始 DB（模拟 Widget 进程视角）。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.allNotes().map(\.id) == [noteM.id])
        #expect(try fresh.noteItems(noteId: noteN.id).isEmpty)   // 级联清空
        #expect(try fresh.noteItems(noteId: noteM.id).count == 1)  // 他签事项不受牵连
    }

    // MARK: - W2-3 移交项 ④：pet_profile → growth_state 级联（note→note_item 级联的镜像钉子）

    @Test func deletePetCascadesGrowthStateAcrossConnections() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        try await store.upsertPet(PetProfile(id: "cat", species: .cat, displayName: "橘猫"))
        try await store.upsertPet(PetProfile(id: "shiba", species: .shiba, displayName: "柴犬"))
        try await store.upsertGrowthState(GrowthState(petId: "cat", fedLevel: 2, streakDays: 3))
        try await store.upsertGrowthState(GrowthState(petId: "shiba", fedLevel: 1))

        // 独立连接裸删 pet 行（store 刻意不设 deletePet API；删除即另一进程的直接写）。
        try await DatabasePool(path: path).write { db in
            _ = try PetProfile.deleteOne(db, key: "cat")
        }

        // 全新独立连接核对原始 DB：被删宠物的养成状态级联清空，他宠不受牵连。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.growthState(petId: "cat") == nil)
        #expect(try fresh.growthState(petId: "shiba") == GrowthState(petId: "shiba", fedLevel: 1))
    }

    // MARK: - W2-3 移交项 ④：假 noteId 的清单项被外键拒绝（throws + 零副作用）

    @Test func noteItemWithBogusNoteIdRejectedByForeignKey() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let ghostNoteID = UUID()

        do {
            try await store.addNoteItem(NoteItem(noteId: ghostNoteID, text: "孤儿事项"))
            Issue.record("指向不存在便签的清单项必须被外键拒绝")
        } catch {
            #expect((error as? DatabaseError)?.message?.contains("FOREIGN KEY") == true)
        }
        // 零副作用：库里不得留下孤儿行。
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.noteItems(noteId: ghostNoteID).isEmpty)
    }
}
