import Foundation
import Testing
@testable import Core

/// 优化批次(2026-10):P0 数据层修复 + P2 历史会话合并的行为钉子。
///
/// 覆盖:①addItem position-on-create(插入序);②createNote(style:) 单事务落库;
/// ③updateNote 历史编辑会话合并;④SharedStore.feedPet 原子喂养;⑤预设解析与
/// 清单进度的 DRY 单一点。
struct DataLayerOptimizationTests {

    private func makePath() -> String {
        TestSupport.makeDatabasePath(prefix: "opt")
    }

    private func makeRepository(path: String) throws -> NoteRepository {
        NoteRepository(store: try SharedStore(databasePath: path))
    }

    private func historyEntries(_ repo: NoteRepository, noteId: UUID) throws -> [HistoryEntry] {
        try repo.history(entityType: .note, entityId: noteId.uuidString)
    }

    private func decode(_ entry: HistoryEntry) throws -> ExportNote {
        try JSONDecoder().decode(ExportNote.self, from: Data(entry.payload.utf8))
    }

    // MARK: - ① addItem position-on-create(插入序)

    @Test func addItemAssignsIncreasingPositionsInInsertionOrder() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "清单宿主")

        let a = try await repo.addItem(to: note.id, text: "第一项")
        let b = try await repo.addItem(to: note.id, text: "第二项")
        let c = try await repo.addItem(to: note.id, text: "第三项")

        // position 依插入序递增(空表起步 0/1/2)——修复:此前恒 0,顺序靠随机 UUID 决胜。
        let positions = [a.position, b.position, c.position]
        #expect(positions == [0, 1, 2])
        // 读回序(noteItems 按 position ASC, id ASC)必须等于插入序。
        let read = try repo.noteItems(noteId: note.id)
        let texts = read.map(\.text)
        #expect(texts == ["第一项", "第二项", "第三项"])
    }

    @Test func addItemContinuesAfterExistingMaxPosition() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let store = try SharedStore(databasePath: path)
        let note = try await repo.createNote(text: "宿主")

        // 预置一条 position=5 的项(种数据走 store 原语,与 createNote 的 MAX+1 模式对齐)。
        try await store.addNoteItem(NoteItem(noteId: note.id, text: "旧项", position: 5))

        let added = try await repo.addItem(to: note.id, text: "新项")
        #expect(added.position == 6, "position 必须接在现有 MAX(position) 之后")
    }

    // MARK: - ② createNote(style:) 单事务落库

    @Test func createNotePersistsStyleWithSingleHistoryEntry() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)

        let note = try await repo.createNote(text: "带色创建", style: "mint")

        #expect(try SharedStore(databasePath: path).allNotes().first?.style == "mint")
        // 单事务一步到位:历史恰好 1 条「创建后像」——不再有补写 style 的第二步 update
        // (两步两事务的崩溃窗口与无语义历史条目一并消失)。
        let entries = try historyEntries(repo, noteId: note.id)
        #expect(entries.count == 1)
        #expect(try decode(entries[0]).style == "mint")
    }

    // MARK: - ③ updateNote 历史编辑会话合并(P2)

    @Test func coalescedUpdatesWithinWindowAppendSinglePreImage() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "会话起点文本")

        // 编辑器真实时序:便签闲置(距上一条历史 > window)后才被编辑——
        // 首次编辑落「会话起点」前像,窗内的后续防抖落盘全部跳过。
        try await Task.sleep(nanoseconds: 80_000_000)
        var edit1 = note
        edit1.text = "编辑一"
        try await repo.updateNote(edit1, history: .coalesce(window: 0.05))
        var edit2 = note
        edit2.text = "编辑二"
        try await repo.updateNote(edit2, history: .coalesce(window: 0.05))

        // 窗内两次落盘:历史 = 1 条 create 后像 + 1 条首编辑前像(会话起点)。
        // 修复前:每次 update 各落一条前像,打字 1 分钟可膨胀上百条。
        let entries = try historyEntries(repo, noteId: note.id)
        #expect(entries.count == 2)
        let preImage = try decode(entries[0])
        #expect(preImage.text == "会话起点文本", "保留的前像必须是会话起点状态")
        // 最终值正常落库。
        #expect(try SharedStore(databasePath: path).allNotes().first?.text == "编辑二")
    }

    /// create 后像同样充当合并锚点:新建后立刻快速编辑,create 条目(内容即会话起点)
    /// 距今 < window → 首次编辑即可跳过——信息零损失(create 后像就是起点状态)。
    @Test func coalesceAnchorsOnCreateEntryForFreshNoteRapidEdits() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "出生即编辑")

        var edit1 = note
        edit1.text = "编辑一"
        try await repo.updateNote(edit1, history: .coalesce(window: 60))
        var edit2 = note
        edit2.text = "编辑二"
        try await repo.updateNote(edit2, history: .coalesce(window: 60))

        // 仅 create 一条;回滚目标 = create 后像(即会话起点)。
        let entries = try historyEntries(repo, noteId: note.id)
        #expect(entries.count == 1)
        #expect(try decode(entries[0]).text == "出生即编辑")
        #expect(try SharedStore(databasePath: path).allNotes().first?.text == "编辑二")
    }

    @Test func coalescedUpdatesAcrossWindowAppendSeparatePreImages() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "起点")

        try await Task.sleep(nanoseconds: 80_000_000)
        var edit1 = note
        edit1.text = "窗内编辑"
        try await repo.updateNote(edit1, history: .coalesce(window: 0.05))
        // 越过窗口(80ms > 50ms):新前像应落——合并是密度上限,不是「整会话只留一条」。
        try await Task.sleep(nanoseconds: 80_000_000)
        var edit2 = note
        edit2.text = "窗外编辑"
        try await repo.updateNote(edit2, history: .coalesce(window: 0.05))

        let entries = try historyEntries(repo, noteId: note.id)
        #expect(entries.count == 3, "create + 两条跨窗前像")
        let newest = try decode(entries[0])
        let older = try decode(entries[1])
        #expect(newest.text == "窗内编辑")
        #expect(older.text == "起点")
    }

    @Test func updateNoteDefaultModeAlwaysAppendsEveryTime() async throws {
        let path = makePath()
        let repo = try makeRepository(path: path)
        let note = try await repo.createNote(text: "起点")

        var edit1 = note
        edit1.text = "编辑一"
        try await repo.updateNote(edit1)
        var edit2 = note
        edit2.text = "编辑二"
        try await repo.updateNote(edit2)

        // 默认 .always 不回归:非编辑器路径(toggle/restore/import)的前像纪律不变。
        #expect(try historyEntries(repo, noteId: note.id).count == 3)
    }

    // MARK: - ④ SharedStore.feedPet 原子喂养(P0-5)

    @Test func feedPetSeedsStateOnFirstCallAndPersists() async throws {
        let path = makePath()
        let store = try SharedStore(databasePath: path)
        try await store.upsertPet(PetProfile(
            id: "pet-1", species: .cat, displayName: "Tabby",
            isSelected: true, acquiredAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        let now = Date(timeIntervalSince1970: 1_800_010_000)
        let fed = try await store.feedPet(petId: "pet-1", now: now)

        #expect(fed.fedLevel == 1)
        #expect(fed.streakDays == 1)
        #expect(fed.lastActiveDay == now)
        // 喂养结果必须已持久化(单写事务内读-改-写完成)。
        let read = try store.growthState(petId: "pet-1")
        #expect(read?.fedLevel == 1)
        #expect(read?.streakDays == 1)
    }

    @Test func feedPetSameDaySecondFeedKeepsStreak() async throws {
        let path = makePath()
        let store = try SharedStore(databasePath: path)
        try await store.upsertPet(PetProfile(
            id: "pet-1", species: .cat, displayName: "Tabby",
            isSelected: true, acquiredAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        let base = Date(timeIntervalSince1970: 1_800_010_000)
        _ = try await store.feedPet(petId: "pet-1", now: base)
        let second = try await store.feedPet(petId: "pet-1", now: base.addingTimeInterval(2 * 3600))

        // 同日再喂:fedLevel 增、streak 不变(GrowthEngine 语义经由原子入口不漂移)。
        #expect(second.fedLevel == 2)
        #expect(second.streakDays == 1)
    }

    // MARK: - ⑤ DRY 单一点(P1-3)

    @Test func presetResolveHandlesKnownUnknownAndNil() {
        #expect(NoteStylePreset.resolve("mint") == .mint)
        #expect(NoteStylePreset.resolve("charcoal") == .charcoal)
        #expect(NoteStylePreset.resolve(nil) == .classicYellow)
        #expect(NoteStylePreset.resolve("bogus") == .classicYellow)
    }

    @Test func checklistProgressComputesDoneCountAndFraction() {
        let items = [
            NoteItem(noteId: UUID(), text: "a", done: true),
            NoteItem(noteId: UUID(), text: "b", done: false),
            NoteItem(noteId: UUID(), text: "c", done: true),
        ]
        #expect(items.doneCount == 2)
        #expect(items.completionFraction == 2.0 / 3.0)

        let empty: [NoteItem] = []
        #expect(empty.doneCount == 0)
        #expect(empty.completionFraction == 0)

        let snapshots = [
            WatchPayload.ItemSnapshot(text: "x", done: false),
            WatchPayload.ItemSnapshot(text: "y", done: true),
        ]
        #expect(snapshots.doneCount == 1)
        #expect(snapshots.completionFraction == 0.5)
    }
}
