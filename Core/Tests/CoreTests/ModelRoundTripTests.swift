import Foundation
import Testing
import GRDB
@testable import Core

/// W2-2:四模型的落库回路（round-trip）与最小持久化 API 语义。
/// 全部走「写入后换独立连接读回」的原始状态核对,杜绝走写入方 accessor 的假阳性。
struct ModelRoundTripTests {

    /// 全新独立数据库路径（每次调用新临时目录,保证跨运行确定性）。
    private func makeDatabasePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawit-w22-model-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("pawit.sqlite3").path
    }

    /// 整秒级固定日期:GRDB Date 以毫秒精度文本持久化,整秒可精确相等比较。
    private func fixedDate(_ epoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    // MARK: - Note:dueDate 往返（nil 与有值）+ upsert 语义

    @Test func noteDueDateRoundTripsNilAndSet() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let noDue = Note(id: UUID(), text: "无到期", createdAt: fixedDate(1))
        let withDue = Note(
            id: UUID(), text: "两小时后喂食", createdAt: fixedDate(2),
            dueDate: fixedDate(1_800_000_000), position: 3
        )
        try await store.upsertNote(noDue)
        try await store.upsertNote(withDue)

        let fresh = try SharedStore(databasePath: path)
        let notes = try fresh.allNotes()
        #expect(notes.count == 2)

        let readNoDue = try #require(notes.first { $0.id == noDue.id })
        #expect(readNoDue.dueDate == nil)
        #expect(readNoDue.position == 0)

        let readWithDue = try #require(notes.first { $0.id == withDue.id })
        #expect(readWithDue.dueDate == fixedDate(1_800_000_000))
        #expect(readWithDue.position == 3)
    }

    @Test func upsertNoteUpdatesInPlace() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let id = UUID()
        try await store.upsertNote(Note(id: id, text: "旧文本", createdAt: fixedDate(1)))
        try await store.upsertNote(
            Note(id: id, text: "新文本", createdAt: fixedDate(1), done: true, position: 5)
        )

        let fresh = try SharedStore(databasePath: path)
        let notes = try fresh.allNotes()
        #expect(notes.count == 1)  // 同主键更新,不产生重复行
        #expect(notes[0].text == "新文本")
        #expect(notes[0].done == true)
        #expect(notes[0].position == 5)
    }

    // MARK: - 排序语义落库:(position, createdAt, id) 三级排序

    @Test func allNotesOrdersByPositionThenCreatedAtThenID() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let sameInstant = fixedDate(1_000_000)
        let idSmall = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idLarge = UUID(uuidString: "FFFF0000-0000-0000-0000-000000000002")!

        // 故意乱序插入,证明顺序来自排序键而非插入序:
        // C(position 2) → A(position 0, 同刻, id 大) → D(position 0, 同刻, id 小) → B(position 1, 更晚)
        let noteC = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, text: "C pos2", createdAt: sameInstant, position: 2)
        let noteA = Note(id: idLarge, text: "A pos0 id大", createdAt: sameInstant, position: 0)
        let noteD = Note(id: idSmall, text: "D pos0 id小", createdAt: sameInstant, position: 0)
        let noteB = Note(id: UUID(), text: "B pos1", createdAt: fixedDate(2_000_000), position: 1)
        for note in [noteC, noteA, noteD, noteB] {
            try await store.upsertNote(note)
        }

        let fresh = try SharedStore(databasePath: path)
        // position 决胜;position 与 createdAt 同值时以 id ASC 决胜（与 firstNote 同族规则）。
        #expect(try fresh.allNotes().map(\.id) == [idSmall, idLarge, noteB.id, noteC.id])
    }

    // MARK: - W2-3 移交项 ②:dueDate 排序决策钉子——有日期升序在前,未设到期殿后

    /// nil-last 决策:SQLite `ORDER BY dueDate ASC` 下 NULL 排在最前(NULL 最小),
    /// 不合用户直觉;`ORDER BY dueDate IS NULL, dueDate ASC, ...` 中 `dueDate IS NULL`
    /// 对非 NULL 行取 0、对 NULL 行取 1,0 排在 1 前 → 有日期者按时间升序打头,无日期殿后。
    /// (用户先看「什么时候到期」,未设到期的自由便签垫底。)
    /// 原始 TEXT 断言把「GRDB .datetime 文本编码下字典序 == 时间序」冻结——防未来
    /// GRDB 存储编码变化(如改 DOUBLE epoch)悄悄破坏 SQL 排序假设。
    @Test func notesOrderedByDueDateIsChronologicalWithUndatedLast() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let dueEarly = fixedDate(1_790_000_000)                    // 早到期
        let dueLater = fixedDate(1_790_000_000 + 30 * 86_400)      // 晚整整一个月(时序 pin 的两个到期日)

        // 乱序插入:先月底、再无到期、再两个同到期的月中行(position 决胜)。
        let late = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: "月底到期", createdAt: fixedDate(2), dueDate: dueLater, position: 5)
        let undated = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: "无到期垫底", createdAt: fixedDate(1))
        let earlyPosHigh = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, text: "月中到期 pos2", createdAt: fixedDate(3), dueDate: dueEarly, position: 2)
        let earlyPosLow = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, text: "月中到期 pos0", createdAt: fixedDate(4), dueDate: dueEarly, position: 0)
        for note in [late, undated, earlyPosHigh, earlyPosLow] {
            try await store.upsertNote(note)
        }

        let fresh = try SharedStore(databasePath: path)
        // 期望序:月中(pos0 → pos2) → 月底 → 未设到期殿后;同 dueDate 内 position 决胜。
        let ordered = try fresh.notesOrderedByDueDate()
        #expect(ordered.map(\.id) == [earlyPosLow.id, earlyPosHigh.id, late.id, undated.id])
        #expect(ordered.map(\.dueDate) == [dueEarly, dueEarly, dueLater, nil])

        // 原始 TEXT 钉子:库里 .datetime 文本按字典序排列必须等于检索出的时间升序——
        // 「字典序 == 时间序」这一 SQL 排序假设被显式冻结。
        let rawDueDates = try await DatabasePool(path: path).read { db in
            try String.fetchAll(db, sql: "SELECT dueDate FROM note WHERE dueDate IS NOT NULL ORDER BY dueDate IS NULL, dueDate ASC")
        }
        #expect(rawDueDates.count == 3)
        #expect(rawDueDates == rawDueDates.sorted())          // 检索序 == 文本字典序
        #expect(rawDueDates.first! < rawDueDates.last!)       // 相距一个月:早 < 晚
    }

    // MARK: - NoteItem:排序 + Note.items(in:) 取数助手

    @Test func noteItemsOrdersByPositionThenIDAndNoteFetchHelperAgrees() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        let note = Note(text: "清单便签", createdAt: fixedDate(1))
        try await store.upsertNote(note)

        let idSmall = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idLarge = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        // 乱序加入:position 同值的两条以 id ASC 决胜。
        try await store.addNoteItem(NoteItem(id: idLarge, noteId: note.id, text: "pos0 id大", position: 0, createdAt: fixedDate(1)))
        try await store.addNoteItem(NoteItem(id: UUID(), noteId: note.id, text: "pos2", position: 2, createdAt: fixedDate(2)))
        try await store.addNoteItem(NoteItem(id: idSmall, noteId: note.id, text: "pos0 id小", position: 0, createdAt: fixedDate(3)))
        try await store.addNoteItem(NoteItem(id: UUID(), noteId: note.id, text: "pos1", position: 1, createdAt: fixedDate(4)))

        let fresh = try SharedStore(databasePath: path)
        let items = try fresh.noteItems(noteId: note.id)
        #expect(items.map(\.text) == ["pos0 id小", "pos0 id大", "pos1", "pos2"])

        // Note.items(in:) 取数助手与 store 的 noteItems 同序同集。
        guard let fetchedNote = try fresh.firstNote() else {
            Issue.record("清单便签必须存在")
            return
        }
        let rawPool = try DatabasePool(path: path)
        let fromHelper = try await rawPool.read { db in
            try fetchedNote.items(in: db)
        }
        #expect(fromHelper == items)
    }

    // MARK: - toggleNoteItem:单事务读-改-写,作用域钉死在 (noteId, itemId)

    @Test func toggleNoteItemFlipsAndPersists() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let note = Note(text: "翻转目标", createdAt: fixedDate(1))
        try await store.upsertNote(note)
        let item = NoteItem(noteId: note.id, text: "事项")
        try await store.addNoteItem(item)

        let firstFlip = try await store.toggleNoteItem(noteId: note.id, itemId: item.id)
        #expect(firstFlip == true)

        // 原始状态核对:独立连接读回持久化结果。
        let fresh = try SharedStore(databasePath: path)
        #expect(try #require(try fresh.noteItems(noteId: note.id).first).done == true)

        let secondFlip = try await fresh.toggleNoteItem(noteId: note.id, itemId: item.id)
        #expect(secondFlip == false)
        #expect(try #require(try SharedStore(databasePath: path).noteItems(noteId: note.id).first).done == false)
    }

    @Test func toggleNoteItemScopedToNoteThrowsForForeignNote() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let noteA = Note(text: "A", createdAt: fixedDate(1))
        let noteB = Note(text: "B", createdAt: fixedDate(2))
        try await store.upsertNote(noteA)
        try await store.upsertNote(noteB)
        let item = NoteItem(noteId: noteA.id, text: "A 的事项")
        try await store.addNoteItem(item)

        // 用 noteB 作用域翻转 A 的 item:必须抛错且零副作用。
        do {
            _ = try await store.toggleNoteItem(noteId: noteB.id, itemId: item.id)
            Issue.record("跨便签翻转必须抛 noteItemNotFound")
        } catch {
            #expect((error as? SharedStoreError) == .noteItemNotFound(noteId: noteB.id, itemId: item.id))
        }
        #expect(try store.noteItems(noteId: noteA.id).first?.done == false)
    }

    // MARK: - PetProfile:往返 + selectedPet

    @Test func petProfileRoundTripsAndSelectedPetWins() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        // 未选中任何宠物时为 nil。
        #expect(try store.selectedPet() == nil)

        let acquired = fixedDate(1_700_000_000)
        try await store.upsertPet(PetProfile(id: "cat", species: .cat, displayName: "橘猫", isSelected: false, acquiredAt: acquired))
        let shiba = PetProfile(id: "shiba", species: .shiba, displayName: "柴犬", isSelected: true, acquiredAt: acquired)
        try await store.upsertPet(shiba)

        let fresh = try SharedStore(databasePath: path)
        let selected = try #require(try fresh.selectedPet())
        #expect(selected == shiba)  // 全字段相等（Equatable 回路）
        #expect(selected.species == .shiba)
        #expect(selected.acquiredAt == acquired)

        // upsert 已存在的行:更新不重复。
        var updated = shiba
        updated.displayName = "柴柴"
        updated.isSelected = false
        try await fresh.upsertPet(updated)
        let after = try SharedStore(databasePath: path)
        #expect(try after.selectedPet() == nil)  // isSelected=false 后无选中
    }

    @Test func petSpeciesPinsSixShippedCases() {
        // 首发六宠:与 art/characters/ 目录一一对应,rawValue 即存储值。
        #expect(PetSpecies.allCases == [.cat, .graycat, .corgi, .shiba, .rabbit, .hamster])
        #expect(PetSpecies.allCases.map(\.rawValue) == ["cat", "graycat", "corgi", "shiba", "rabbit", "hamster"])
    }

    /// 防御性解码:库里出现未知 species（脏数据/旧版本写入）必须显式抛错,不静默归一。
    @Test func corruptSpeciesRowIsRejectedDefensively() throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        try DatabasePool(path: path).write { db in
            try db.execute(
                sql: "INSERT INTO pet_profile (id, species, displayName, isSelected, acquiredAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["x", "dragon", "不明生物", 1, fixedDate(1)]
            )
        }

        do {
            _ = try store.selectedPet()
            Issue.record("未知 species 必须抛 corruptPetSpecies")
        } catch {
            #expect((error as? SharedStoreError) == .corruptPetSpecies("dragon"))
        }
    }

    // MARK: - GrowthState:默认值回路 + 全字段往返 + SQL DEFAULT 钉子

    @Test func growthStateDefaultsAndFullRoundTrip() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)

        // 全默认:fedLevel/streakDays 0、lastActiveDay nil、装扮空数组。
        let defaults = GrowthState(petId: "cat")
        try await store.upsertPet(PetProfile(id: "cat", species: .cat, displayName: "橘猫"))
        try await store.upsertGrowthState(defaults)
        #expect(try store.growthState(petId: "cat") == defaults)

        // 全字段往返。
        let full = GrowthState(
            petId: "shiba", fedLevel: 3, streakDays: 7,
            lastActiveDay: fixedDate(1_800_000_000), unlockedOutfits: "[\"bowtie\",\"crown\"]"
        )
        try await store.upsertPet(PetProfile(id: "shiba", species: .shiba, displayName: "柴犬"))
        try await store.upsertGrowthState(full)
        #expect(try store.growthState(petId: "shiba") == full)
        #expect(try store.growthState(petId: "unknown") == nil)

        // SQL DEFAULT 钉子:绕过模型裸插一行（只给 petId）,列默认值必须就位。
        // 外键在裸连接上同样生效:先落 pet_profile("rabbit"),否则 FK 拒绝。
        try await store.upsertPet(PetProfile(id: "rabbit", species: .rabbit, displayName: "兔子"))
        try await DatabasePool(path: path).write { db in
            try db.execute(sql: "INSERT INTO growth_state (petId) VALUES (?)", arguments: ["rabbit"])
        }
        let rawDefaults = try await DatabasePool(path: path).read {
            db -> (fedLevel: Int, streakDays: Int, lastActiveDay: Date?, unlockedOutfits: String)? in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT fedLevel, streakDays, lastActiveDay, unlockedOutfits FROM growth_state WHERE petId = ?",
                arguments: ["rabbit"]
            ) else { return nil }
            return (row["fedLevel"], row["streakDays"], row["lastActiveDay"], row["unlockedOutfits"])
        }
        guard let rawRow = rawDefaults else {
            Issue.record("裸插的 growth_state 行必须存在")
            return
        }
        #expect(rawRow.fedLevel == 0)
        #expect(rawRow.streakDays == 0)
        #expect(rawRow.lastActiveDay == nil)
        #expect(rawRow.unlockedOutfits == "[]")
    }
}
