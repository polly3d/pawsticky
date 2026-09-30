import Foundation
import Testing
import GRDB
@testable import Core

/// W2-4:NoteRepository——App 实际调用的门面。断言全部围绕「信任功能」契约:
/// 历史 + 变更同事务(同生共死)、PRE-change 快照可回滚、保留窗 7 天、append-only。
struct NoteRepositoryTests {

    /// 全新独立库(每次新临时目录);测试要拿 path 做原始状态核对,故显式持有。
    private func makePath() -> String {
        TestSupport.makeDatabasePath(prefix: "w24-repo")
    }

    private func makeRepository(path: String) throws -> NoteRepository {
        NoteRepository(store: try SharedStore(databasePath: path))
    }

    /// 原始状态核对:绕过一切业务 accessor,直接数 history_log 总行数。
    private func totalHistoryRows(_ path: String) throws -> Int {
        try SharedStore(databasePath: path).read { db in try HistoryEntry.fetchCount(db) }
    }

    /// 整秒级固定日期:GRDB 毫秒精度文本编码下可精确相等比较。
    private func fixed(_ epoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    // MARK: - createNote:落库 + 「创建」快照(后像)

    @Test func createNotePersistsAndAppendsCreatedSnapshot() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)

        let due = fixed(1_800_000_000)
        let note = try await repo.createNote(text: "铲屎", dueDate: due)

        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.allNotes().map(\.id) == [note.id])
        #expect(try fresh.allNotes().first?.text == "铲屎")

        let entries = try makeRepository(path: path).history(entityType: .note, entityId: note.id.uuidString)
        #expect(entries.count == 1)
        let snapshot = try JSONDecoder().decode(ExportNote.self, from: Data(entries[0].payload.utf8))
        #expect(snapshot.text == "铲屎")          // create 条目记录「出现了什么」
        #expect(snapshot.dueDate == due)
        #expect(entries[0].entityType == .note)
    }

    // MARK: - updateNote:PRE-change 快照(前像)——本表存在的意义

    @Test func updateNoteAppendsPreChangeSnapshotNewestFirst() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "旧文本")
        try await Task.sleep(nanoseconds: 5_000_000)  // 隔开 changedAt 毫秒精度,顺序可断言

        var edited = note
        edited.text = "新文本"
        edited.done = true
        try await repo.updateNote(edited)

        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.allNotes().first?.text == "新文本")

        let entries = try makeRepository(path: path).history(entityType: .note, entityId: note.id.uuidString)
        #expect(entries.count == 2)
        // 最新在前:第一条是 update 的前像(text/done 都是改前值)——恢复即回到改前。
        let preChange = try JSONDecoder().decode(ExportNote.self, from: Data(entries[0].payload.utf8))
        #expect(preChange.text == "旧文本")
        #expect(preChange.done == false)
        // 次新是 create 条目。
        let created = try JSONDecoder().decode(ExportNote.self, from: Data(entries[1].payload.utf8))
        #expect(created.text == "旧文本")
    }

    /// updateNote 是「更新」不是 upsert:目标行不存在必须抛错——静默插入会把陈旧对象
    /// 变成「复活的数据」,与零丢数据承诺背道而驰。
    @Test func updateNoteOnMissingRowThrowsWithoutHistory() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let ghost = Note(id: UUID(), text: "幽灵")

        do {
            try await repo.updateNote(ghost)
            Issue.record("更新不存在的便签必须抛 noteNotFound")
        } catch let error as NoteRepositoryError {
            #expect(error == .noteNotFound(ghost.id))
        }
        #expect(try totalHistoryRows(path) == 0)  // 零副作用
    }

    // MARK: - deleteNote:便签 + 级联清单项全部留前像

    @Test func deleteNoteSnapshotsNoteAndCascadeItemsBeforeRemoval() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "将被误删")
        let itemA = try await repo.addItem(to: note.id, text: "事项A")
        let itemB = try await repo.addItem(to: note.id, text: "事项B")
        try await Task.sleep(nanoseconds: 5_000_000)

        try await repo.deleteNote(id: note.id)

        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.allNotes().isEmpty)             // 级联:便签与清单项一并消失
        #expect(try fresh.noteItems(noteId: note.id).isEmpty)

        let repo2 = try makeRepository(path: path)
        // 三份前像各自可查:note 一条、item 两条,payload 都是删除前的整行。
        let noteEntries = try repo2.history(entityType: .note, entityId: note.id.uuidString)
        #expect(noteEntries.count == 2)  // create + delete 前像
        let deletedSnapshot = try JSONDecoder().decode(ExportNote.self, from: Data(noteEntries[0].payload.utf8))
        #expect(deletedSnapshot.text == "将被误删")

        for item in [itemA, itemB] {
            let itemEntries = try repo2.history(entityType: .noteItem, entityId: item.id.uuidString)
            #expect(itemEntries.count == 2)  // addItem 的 create + deleteNote 的删除前像
            let snapshot = try JSONDecoder().decode(ExportNoteItem.self, from: Data(itemEntries[0].payload.utf8))
            #expect(snapshot.noteId == note.id.uuidString)
        }
    }

    // MARK: - restore:从快照回滚

    @Test func restoreReinsertsDeletedNoteWithAllColumns() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let original = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            text: "误删找回", createdAt: fixed(1_000), done: true,
            dueDate: fixed(1_800_000_000), position: 3
        )
        try await SharedStore(databasePath: path).upsertNote(original)
        try await repo.updateNote(original)  // 留一条前像
        try await Task.sleep(nanoseconds: 5_000_000)
        try await repo.deleteNote(id: original.id)

        let fresh = try makeRepository(path: path)
        let entries = try fresh.history(entityType: .note, entityId: original.id.uuidString)
        let preDeleteEntry = try #require(entries.first)  // 最新 = 删除前像
        try await repo.restore(entityType: .note, entityId: original.id.uuidString, historyEntryId: preDeleteEntry.id)

        let after = try SharedStore(databasePath: path)
        #expect(try after.allNotes() == [original])  // 全列复原(含 createdAt/done/dueDate/position)
    }

    /// 删便签连带级联删清单项;先恢复清单项(父便签尚缺)必须被拒——
    /// restore 不静默复活父行(父行有自己的条目,先恢复父行是显式路径)。
    @Test func restoreItemRejectsWhileParentNoteMissingThenSucceedsAfterParentRestored() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "父便签")
        let item = try await repo.addItem(to: note.id, text: "孤儿子项")
        // 记录删除前库内持久态(ms 截断后),作为恢复后全等比较的基准。
        let persistedBefore = try #require(
            try SharedStore(databasePath: path).noteItems(noteId: note.id).first
        )
        try await Task.sleep(nanoseconds: 5_000_000)
        try await repo.deleteNote(id: note.id)

        let fresh = try makeRepository(path: path)
        let itemEntry = try #require(
            try fresh.history(entityType: .noteItem, entityId: item.id.uuidString).first
        )

        do {
            try await repo.restore(entityType: .noteItem, entityId: item.id.uuidString, historyEntryId: itemEntry.id)
            Issue.record("父便签缺失时恢复清单项必须被拒")
        } catch let error as NoteRepositoryError {
            #expect(error == .restoreParentMissing(parentType: .note, parentId: note.id.uuidString))
        }

        // 父行先行恢复后,子项恢复走通。
        let noteEntry = try #require(
            try fresh.history(entityType: .note, entityId: note.id.uuidString).first
        )
        try await repo.restore(entityType: .note, entityId: note.id.uuidString, historyEntryId: noteEntry.id)
        try await repo.restore(entityType: .noteItem, entityId: item.id.uuidString, historyEntryId: itemEntry.id)

        let after = try SharedStore(databasePath: path)
        #expect(try after.noteItems(noteId: note.id) == [persistedBefore])
    }

    /// restore 本身也是变更:同样落快照(恢复动作进入审计链)。
    @Test func restoreAppendsItsOwnHistoryEntry() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "一轮")
        var edited = note
        edited.text = "二轮"
        try await repo.updateNote(edited)
        try await Task.sleep(nanoseconds: 5_000_000)

        let fresh = try makeRepository(path: path)
        let updateEntry = try #require(
            try fresh.history(entityType: .note, entityId: note.id.uuidString).first
        )
        try await repo.restore(entityType: .note, entityId: note.id.uuidString, historyEntryId: updateEntry.id)

        let fresh2 = try makeRepository(path: path)
        let entries = try fresh2.history(entityType: .note, entityId: note.id.uuidString)
        #expect(entries.count == 3)  // create → update 前像 → restore 前像
        #expect(try SharedStore(databasePath: path).allNotes().first?.text == "一轮")
    }

    @Test func restoreWithUnknownEntryThrows() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "正文")
        let ghostEntryID = UUID()

        do {
            try await repo.restore(entityType: .note, entityId: note.id.uuidString, historyEntryId: ghostEntryID)
            Issue.record("不存在的历史条目必须抛错")
        } catch let error as NoteRepositoryError {
            #expect(error == .historyEntryNotFound(entityType: .note, entityId: note.id.uuidString, historyEntryId: ghostEntryID))
        }
    }

    /// entityType/entityId 与条目不匹配同样拒绝(防拿 A 实体的条目恢复 B 实体)。
    @Test func restoreRejectsEntityTypeMismatch() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "正文")
        let entry = try #require(
            try makeRepository(path: path).history(entityType: .note, entityId: note.id.uuidString).first
        )

        do {
            try await repo.restore(
                entityType: .noteItem, entityId: note.id.uuidString, historyEntryId: entry.id
            )
            Issue.record("entityType 不匹配必须拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .historyEntryNotFound(
                entityType: .noteItem, entityId: note.id.uuidString, historyEntryId: entry.id
            ))
        }
    }

    // MARK: - addItem / toggleItem / deleteItem:原子契约 + 前像

    @Test func addItemToGhostNoteThrowsWithoutAnyHistory() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let ghost = UUID()

        do {
            _ = try await repo.addItem(to: ghost, text: "孤儿")
            Issue.record("向不存在的便签加清单项必须抛错")
        } catch let error as NoteRepositoryError {
            #expect(error == .noteNotFound(ghost))
        }
        #expect(try totalHistoryRows(path) == 0)
    }

    /// toggleItem 委托 store 的原子读-改-写本体(非 upsert 翻转),并落 toggle 前像。
    @Test func toggleItemTogglesAndSnapshotsPreChangeState() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "清单")
        let item = try await repo.addItem(to: note.id, text: "事项")
        try await Task.sleep(nanoseconds: 5_000_000)

        let flipped = try await repo.toggleItem(noteId: note.id, itemId: item.id)
        #expect(flipped == true)

        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.noteItems(noteId: note.id).first?.done == true)
        let entries = try makeRepository(path: path).history(entityType: .noteItem, entityId: item.id.uuidString)
        #expect(entries.count == 2)
        let preToggle = try JSONDecoder().decode(ExportNoteItem.self, from: Data(entries[0].payload.utf8))
        #expect(preToggle.done == false)  // 前像:翻转前的 done
    }

    /// 原子性钉子:翻转失败(item 不存在)必须连同历史一起回滚——历史与变更同事务,
    /// 若历史被写进了独立事务,这里的总行数会 +1。
    @Test func failedToggleRollsBackHistoryWithMutation() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "正文")
        let ghostItemID = UUID()
        let baseline = try totalHistoryRows(path)

        do {
            _ = try await repo.toggleItem(noteId: note.id, itemId: ghostItemID)
            Issue.record("翻转不存在的清单项必须抛错")
        } catch let error as SharedStoreError {
            #expect(error == .noteItemNotFound(noteId: note.id, itemId: ghostItemID))
        }
        #expect(try totalHistoryRows(path) == baseline)
    }

    @Test func deleteItemSnapshotsPreChangeRowAndRestoreBringsDoneStateBack() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "清单")
        let item = try await repo.addItem(to: note.id, text: "已办事项")
        _ = try await repo.toggleItem(noteId: note.id, itemId: item.id)  // done → true
        // 删除前先记录库内持久态(ms 截断后),作为恢复后全等比较的基准。
        let persistedBefore = try #require(
            try SharedStore(databasePath: path).noteItems(noteId: note.id).first
        )
        try await Task.sleep(nanoseconds: 5_000_000)

        try await repo.deleteItem(noteId: note.id, itemId: item.id)
        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.noteItems(noteId: note.id).isEmpty)

        let entry = try #require(
            try makeRepository(path: path).history(entityType: .noteItem, entityId: item.id.uuidString).first
        )
        try await repo.restore(entityType: .noteItem, entityId: item.id.uuidString, historyEntryId: entry.id)

        let after = try SharedStore(databasePath: path)
        #expect(try after.noteItems(noteId: note.id) == [persistedBefore])
    }

    @Test func deleteItemOnMissingItemThrowsWithoutHistory() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "正文")
        let ghostItemID = UUID()
        let baseline = try totalHistoryRows(path)

        do {
            try await repo.deleteItem(noteId: note.id, itemId: ghostItemID)
            Issue.record("删除不存在的清单项必须抛错")
        } catch let error as SharedStoreError {
            #expect(error == .noteItemNotFound(noteId: note.id, itemId: ghostItemID))
        }
        #expect(try totalHistoryRows(path) == baseline)
    }

    // MARK: - history(for:):最新在前(含同一毫秒的插入序决胜)

    @Test func historyReturnsNewestFirstIncludingSameMillisecondTies() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "一")
        var note2 = note
        note2.text = "二"
        try await repo.updateNote(note2)
        note2.text = "三"
        try await repo.updateNote(note2)  // 快速连击:changedAt 可能同毫秒

        let fresh = try makeRepository(path: path)
        let entries = try fresh.history(entityType: .note, entityId: note.id.uuidString)
        #expect(entries.count == 3)
        // 时间倒序;同毫秒并列时以插入序(rowid)决胜——最新的插入必须排最前。
        let payloads = try entries.map { entry in
            try JSONDecoder().decode(ExportNote.self, from: Data(entry.payload.utf8)).text
        }
        #expect(payloads == ["二", "一", "一"])  // 最新前像(二轮前) → 一轮前像 → create 后像
    }

    // MARK: - 生产接入点

    /// 进程级单池包装:模拟器宿主带 entitlement,必须能拿到仓库实例(生产入口冒烟)。
    @Test func cachedAppGroupReturnsRepository() throws {
        guard SharedStore.appGroupDatabasePath() != nil else {
            return  // 宿主无 entitlement 时跳过(与 SharedStoreTests 的 appGroup 路径测试同口径)
        }
        #expect(NoteRepository.cachedAppGroup() != nil)
    }

    // MARK: - 保留期:append 顺手清走 7 天前条目(retention,不是对记录的修订)

    @Test func appendPrunesOnlyEntriesOlderThanSevenDays() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)

        // 直接入库三条固定 changedAt 的旧条目:8/9 天前(过期)与 6 天前(存活)。
        let day: TimeInterval = 86_400
        try await DatabasePool(path: path).write { db in
            for daysAgo in [8.0, 9.0] {
                try HistoryEntry(
                    id: UUID(), entityType: .note, entityId: "stale-\(daysAgo)",
                    payload: "{}", changedAt: Date(timeIntervalSinceNow: -daysAgo * day)
                ).insert(db)
            }
            try HistoryEntry(
                id: UUID(), entityType: .note, entityId: "recent",
                payload: "{}", changedAt: Date(timeIntervalSinceNow: -6 * day)
            ).insert(db)
        }

        _ = try await repo.createNote(text: "触发 prune 的新变更")  // append 内含保留期清理

        let fresh = try makeRepository(path: path)
        #expect(try fresh.history(entityType: .note, entityId: "stale-8.0").isEmpty)
        #expect(try fresh.history(entityType: .note, entityId: "stale-9.0").isEmpty)
        #expect(try fresh.history(entityType: .note, entityId: "recent").count == 1)  // 未过期:保留
    }
}
