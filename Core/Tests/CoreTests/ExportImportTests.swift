import Foundation
import Testing
import GRDB
import CryptoKit
@testable import Core

/// W2-4:导出/导入——「零丢数据」的用户可见半边(plan §7-P2 换机协议)。
/// DoD 钉子:export → 新库 import → 全部数据一致;口令加密走 CryptoKit AES-GCM + HKDF。
struct ExportImportTests {

    private func makePath(_ tag: String) -> String {
        TestSupport.makeDatabasePath(prefix: "w24-xfer-\(tag)")
    }

    private func makeRepository(path: String) throws -> NoteRepository {
        NoteRepository(store: try SharedStore(databasePath: path))
    }

    /// 原始状态核对:直接从连接读全量四表(绕过业务 accessor)。
    private func fullState(_ path: String) throws -> (
        notes: [Note], items: [NoteItem], pets: [PetProfile], states: [GrowthState]
    ) {
        try SharedStore(databasePath: path).read { db in
            (
                notes: try Note.order(Column("position").asc, Column("createdAt").asc, Column("id").asc).fetchAll(db),
                items: try NoteItem.order(Column("noteId").asc, Column("position").asc, Column("id").asc).fetchAll(db),
                pets: try PetProfile.order(Column("id").asc).fetchAll(db),
                states: try GrowthState.order(Column("petId").asc).fetchAll(db)
            )
        }
    }

    /// 种子库:两种便签(一有到期一手动排序)、三条清单项(一已勾)、两宠(一选中)、两养成态(一有装扮)。
    private func seed(_ path: String) async throws {
        let store = try SharedStore(databasePath: path)
        let noteA = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            text: "带到期", createdAt: Date(timeIntervalSince1970: 1_000),
            dueDate: Date(timeIntervalSince1970: 1_800_000_000), position: 1
        )
        let noteB = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            text: "手动排序在前", createdAt: Date(timeIntervalSince1970: 2_000), position: 0
        )
        try await store.upsertNote(noteA)
        try await store.upsertNote(noteB)
        try await store.addNoteItem(NoteItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            noteId: noteA.id, text: "已办事项", done: true,
            position: 0, createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        try await store.addNoteItem(NoteItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            noteId: noteA.id, text: "待办事项", position: 1, createdAt: Date(timeIntervalSince1970: 4_000)
        ))
        try await store.addNoteItem(NoteItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            noteId: noteB.id, text: "另一签的事项", createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        try await store.upsertPet(PetProfile(
            id: "cat", species: .cat, displayName: "橘猫",
            isSelected: true, acquiredAt: Date(timeIntervalSince1970: 6_000)
        ))
        try await store.upsertPet(PetProfile(
            id: "shiba", species: .shiba, displayName: "柴犬", acquiredAt: Date(timeIntervalSince1970: 7_000)
        ))
        try await store.upsertGrowthState(GrowthState(
            petId: "cat", fedLevel: 3, streakDays: 7,
            lastActiveDay: Date(timeIntervalSince1970: 8_000),
            unlockedOutfits: "[\"bowtie\",\"crown\"]"
        ))
        try await store.upsertGrowthState(GrowthState(petId: "shiba", fedLevel: 1))
    }

    // MARK: - 信封格式 v1

    @Test func plaintextEnvelopePinsFormatVersionAndPayloadShape() async throws {
        let path = makePath("env")
        try await seed(path)
        let repo = try makeRepository(path: path)

        let data = try await repo.export(passphrase: nil)

        let envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        #expect(envelope.format == "pawit.export")
        #expect(envelope.version == 1)
        #expect(envelope.salt == nil)                       // 明文:无盐
        // payload 是明文 JSON 字符串(非 base64、非加密),可直接解码。
        let payloadData = Data(envelope.payload.utf8)
        let payload = try JSONDecoder().decode(ExportPayload.self, from: payloadData)
        #expect(payload.notes.count == 2)
        #expect(payload.noteItems.count == 3)
        #expect(payload.petProfiles.count == 2)
        #expect(payload.growthStates.count == 2)
        // 导出顺序走引擎排序(稳定输出契约):position 0 的 B 在前。
        #expect(payload.notes.map(\.text) == ["手动排序在前", "带到期"])
    }

    // MARK: - DoD:export → 新库 import → 全量一致

    @Test func roundTripThroughFreshStorePreservesEverything() async throws {
        let source = makePath("rt-src")
        let target = makePath("rt-dst")
        try await seed(source)
        let repo = try makeRepository(path: source)

        let data = try await repo.export(passphrase: nil)
        try await makeRepository(path: target).`import`(data: data, passphrase: nil)

        let before = try fullState(source)
        let after = try fullState(target)
        #expect(after.notes == before.notes)
        #expect(after.items == before.items)
        #expect(after.pets == before.pets)
        #expect(after.states == before.states)

        // 独立连接再核对一遍(模拟换机后全新进程视角)。
        let freshAfter = try fullState(target)
        #expect(freshAfter.notes.count == 2)
        #expect(freshAfter.pets.first { $0.isSelected }?.id == "cat")
    }

    // MARK: - 口令加密:AES-GCM + HKDF-SHA256

    @Test func encryptedRoundTripWithPassphrase() async throws {
        let source = makePath("enc-src")
        let target = makePath("enc-dst")
        try await seed(source)
        let repo = try makeRepository(path: source)

        let data = try await repo.export(passphrase: "喵呜123!")

        // 信封:有盐、KDF 参数在案、payload 是 base64 密文(不是明文 JSON)。
        let envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        #expect(envelope.salt != nil)
        #expect(envelope.kdf?.algorithm == "pbkdf2-hmac-sha256")  // KDF 参数入信封
        #expect(envelope.kdf?.iterations == 100_000)
        #expect(Data(base64Encoded: envelope.payload) != nil)  // payload 是 base64 密文
        #expect(!envelope.payload.hasPrefix("{"))

        try await makeRepository(path: target).`import`(data: data, passphrase: "喵呜123!")

        let before = try fullState(source)
        let after = try fullState(target)
        #expect(after == before)
    }

    @Test func wrongPassphraseThrowsDecryptionFailed() async throws {
        let source = makePath("wrongpw")
        try await seed(source)
        let repo = try makeRepository(path: source)
        let data = try await repo.export(passphrase: "正确口令")

        do {
            try await makeRepository(path: makePath("wrongpw-dst")).`import`(data: data, passphrase: "错口令")
            Issue.record("错误口令必须抛 decryptionFailed")
        } catch let error as NoteRepositoryError {
            #expect(error == .decryptionFailed)
        }
    }

    @Test func encryptedEnvelopeWithoutPassphraseThrowsPassphraseRequired() async throws {
        let source = makePath("nopw")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: "口令")

        do {
            try await makeRepository(path: makePath("nopw-dst")).`import`(data: data, passphrase: nil)
            Issue.record("加密信封缺口令必须抛 passphraseRequired")
        } catch let error as NoteRepositoryError {
            #expect(error == .passphraseRequired)
        }
    }

    @Test func plaintextEnvelopeWithPassphraseThrowsUnexpectedPassphrase() async throws {
        let source = makePath("plainpw")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        do {
            try await makeRepository(path: makePath("plainpw-dst")).`import`(data: data, passphrase: "多给了口令")
            Issue.record("明文信封给口令必须抛 unexpectedPassphrase(口径错配,不猜)")
        } catch let error as NoteRepositoryError {
            #expect(error == .unexpectedPassphrase)
        }
    }

    // MARK: - 导入校验:任一违规 → 整包拒绝(reject-all),零副作用

    /// 构造改过的导出包:解码明文信封 → 改 payload JSON → 重封装。
    private func mutatePayload(
        _ data: Data, mutate: (inout [String: Any]) -> Void
    ) throws -> Data {
        let envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        try #require(envelope.salt == nil)
        var payloadJSON = try JSONSerialization.jsonObject(with: Data(envelope.payload.utf8)) as! [String: Any]
        mutate(&payloadJSON)
        let mutatedPayloadData = try JSONSerialization.data(
            withJSONObject: payloadJSON, options: [.sortedKeys]
        )
        let mutatedEnvelope = ExportEnvelope(
            format: envelope.format, version: envelope.version,
            salt: nil, kdf: nil, payload: String(data: mutatedPayloadData, encoding: .utf8)!
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(mutatedEnvelope)
    }

    @Test func unknownSpeciesRejectsWholeImportLeavingStoreUntouched() async throws {
        let source = makePath("species-src")
        let target = makePath("species-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)
        try await seed(target)  // 目标库非空:被拒导入不得清场

        let poisoned = try mutatePayload(data) { payload in
            var pets = payload["petProfiles"] as! [[String: Any]]
            pets[0]["species"] = "dragon"
            payload["petProfiles"] = pets
        }

        do {
            try await makeRepository(path: target).`import`(data: poisoned, passphrase: nil)
            Issue.record("未知 species 必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .unknownSpecies("dragon"))
        }
        // 零副作用:目标库原样(reject-all,不是尽力而为的部分导入)。
        #expect(try fullState(target).notes.count == 2)
        #expect(try fullState(target).pets.map(\.id) == ["cat", "shiba"])
    }

    @Test func orphanedNoteItemRejectsWholeImport() async throws {
        let source = makePath("orphan-src")
        let target = makePath("orphan-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let poisoned = try mutatePayload(data) { payload in
            var notes = payload["notes"] as! [[String: Any]]
            notes.removeFirst()  // 摘掉 position 0 的 B2,留下它的清单项 → 孤儿
            payload["notes"] = notes
        }

        let orphanNoteId = "00000000-0000-0000-0000-0000000000B2"
        do {
            try await makeRepository(path: target).`import`(data: poisoned, passphrase: nil)
            Issue.record("孤儿清单项必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .orphanedNoteItem(noteId: orphanNoteId))
        }
        // 目标库本来为空:导入未落一行(不是尽力而为的部分导入)。
        #expect(try fullState(target).notes.isEmpty)
        #expect(try fullState(target).items.isEmpty)
    }

    @Test func growthStateWithoutPetRejectsWholeImport() async throws {
        let source = makePath("gs-src")
        let target = makePath("gs-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let poisoned = try mutatePayload(data) { payload in
            var states = payload["growthStates"] as! [[String: Any]]
            states[0]["petId"] = "ghost-pet"
            payload["growthStates"] = states
        }

        do {
            try await makeRepository(path: target).`import`(data: poisoned, passphrase: nil)
            Issue.record("养成状态缺父宠物必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .growthStateWithoutPet(petId: "ghost-pet"))
        }
    }

    @Test func duplicateEntityIDInImportRejected() async throws {
        let source = makePath("dup-src")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let poisoned = try mutatePayload(data) { payload in
            var notes = payload["notes"] as! [[String: Any]]
            notes.append(notes[0])  // 同 id 重复
            payload["notes"] = notes
        }

        do {
            try await makeRepository(path: makePath("dup-dst")).`import`(data: poisoned, passphrase: nil)
            Issue.record("重复实体 id 必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .duplicateEntityInImport("note"))
        }
    }

    // MARK: - 损坏/陌生信封

    @Test func malformedDataThrowsMalformedEnvelope() async throws {
        let repo = try makeRepository(path: makePath("malformed"))
        for garbage in [Data("不是 JSON".utf8), Data("{}".utf8), Data("[1,2,3]".utf8)] {
            do {
                try await repo.`import`(data: garbage, passphrase: nil)
                Issue.record("损坏数据必须抛 malformedEnvelope")
            } catch {
                #expect(error is NoteRepositoryError)
            }
        }
    }

    @Test func unknownFormatOrVersionRejected() async throws {
        let repo = try makeRepository(path: makePath("version"))
        let wrongFormat = try JSONEncoder().encode(ExportEnvelope(format: "other.app", version: 1, salt: nil, kdf: nil, payload: "{}"))
        let wrongVersion = try JSONEncoder().encode(ExportEnvelope(format: "pawit.export", version: 999, salt: nil, kdf: nil, payload: "{}"))

        do {
            try await repo.`import`(data: wrongFormat, passphrase: nil)
            Issue.record("陌生 format 必须拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .unsupportedFormat("other.app"))
        }
        do {
            try await repo.`import`(data: wrongVersion, passphrase: nil)
            Issue.record("陌生 version 必须拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .unsupportedVersion(999))
        }
    }

    // MARK: - replace-all 语义 + 双侧快照(坏导入可回滚的关键)

    @Test func importReplacesExistingDataAndSnapshotsBothSidesOfTheSwap() async throws {
        let source = makePath("rep-src")
        let target = makePath("rep-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        // 目标库先有自己的数据:一条便签 + 一条清单项。
        let targetRepo = try makeRepository(path: target)
        let existing = try await targetRepo.createNote(text: "将被替换覆盖")
        let existingItem = try await targetRepo.addItem(to: existing.id, text: "旧事项")

        try await targetRepo.`import`(data: data, passphrase: nil)

        // replace-all:目标库现在与源库完全一致,旧数据一行不剩。
        let before = try fullState(source)
        let after = try fullState(target)
        #expect(after.notes == before.notes)
        #expect(after.items == before.items)
        #expect(after.pets == before.pets)
        #expect(after.states == before.states)

        let fresh = try makeRepository(path: target)
        // 被覆盖的旧行留了删除前像:坏导入后可以据此回滚。
        let oldNoteEntries = try fresh.history(entityType: .note, entityId: existing.id.uuidString)
        let oldSnapshot = try JSONDecoder().decode(ExportNote.self, from: Data(oldNoteEntries[0].payload.utf8))
        #expect(oldSnapshot.text == "将被替换覆盖")
        let oldItemEntries = try fresh.history(entityType: .noteItem, entityId: existingItem.id.uuidString)
        #expect(try JSONDecoder().decode(ExportNoteItem.self, from: Data(oldItemEntries[0].payload.utf8)).text == "旧事项")
        // 导入的每一行也各留一条「创建」记录。
        for imported in before.notes {
            let entries = try fresh.history(entityType: .note, entityId: imported.id.uuidString)
            #expect(entries.count == 1)
        }
    }

    /// 宠物/养成态的恢复路径:导入落下的「创建」条目可寻址,restore 覆盖现状、
    /// 且养成态在父宠物缺失时被拒(与清单项→便签同一纪律)。
    @Test func restorePetProfileAndGrowthStateWithParentCheck() async throws {
        let source = makePath("restore-src")
        let target = makePath("restore-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)
        try await makeRepository(path: target).`import`(data: data, passphrase: nil)
        let repo = try makeRepository(path: target)

        // 破坏目标库:宠物改名去选中、养成态喂食清零。
        try await SharedStore(databasePath: target).upsertPet(PetProfile(
            id: "cat", species: .cat, displayName: "被改名", isSelected: false,
            acquiredAt: Date(timeIntervalSince1970: 99_000)
        ))
        try await SharedStore(databasePath: target).upsertGrowthState(GrowthState(petId: "cat"))

        // 从导入条目恢复:全字段回到导入时刻。
        let petEntry = try #require(repo.history(entityType: .petProfile, entityId: "cat").first)
        try await repo.restore(entityType: .petProfile, entityId: "cat", historyEntryId: petEntry.id)
        #expect(try SharedStore(databasePath: target).selectedPet()?.displayName == "橘猫")

        let growthEntry = try #require(repo.history(entityType: .growthState, entityId: "cat").first)
        try await repo.restore(entityType: .growthState, entityId: "cat", historyEntryId: growthEntry.id)
        #expect(try SharedStore(databasePath: target).growthState(petId: "cat")?.fedLevel == 3)

        // 父宠物被删后,其养成态恢复被拒(restoreParentMissing,不复活父行)。
        try await DatabasePool(path: target).write { db in
            _ = try PetProfile.deleteOne(db, key: "shiba")
        }
        let shibaEntry = try #require(repo.history(entityType: .growthState, entityId: "shiba").first)
        do {
            try await repo.restore(entityType: .growthState, entityId: "shiba", historyEntryId: shibaEntry.id)
            Issue.record("父宠物缺失时恢复养成态必须被拒")
        } catch let error as NoteRepositoryError {
            #expect(error == .restoreParentMissing(parentType: .petProfile, parentId: "shiba"))
        }
    }

    // MARK: - 评审修复(Important):非法 UUID 文本的 typed-reject(替代静默重铸)

    /// 便签 id 为非法 UUID 文本 → `.malformedEntityID` 整包拒绝,目标库原样
    /// (此前 `asRow` 会 `?? UUID()` 静默重铸新 id——数据被无声改写,零丢数据红线)。
    @Test func garbageNoteIDInImportRejectedTyped() async throws {
        let source = makePath("uuid-src")
        let target = makePath("uuid-dst")
        try await seed(source)
        try await seed(target)  // 目标库非空:被拒导入不得清场
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let poisoned = try mutatePayload(data) { payload in
            var notes = payload["notes"] as! [[String: Any]]
            notes[0]["id"] = "不是UUID"
            payload["notes"] = notes
        }

        do {
            try await makeRepository(path: target).`import`(data: poisoned, passphrase: nil)
            Issue.record("非法 UUID 便签 id 必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .malformedEntityID("不是UUID"))
        }
        #expect(try fullState(target).notes.count == 2)  // 零副作用
    }

    /// 清单项 noteId 为非法 UUID 文本 → `.malformedEntityID`(先于孤儿校验:
    /// 「格式非法」与「指向缺失」是两种错误,前者更早)。
    @Test func garbageItemNoteIDInImportRejectedTyped() async throws {
        let source = makePath("uuid-item-src")
        let target = makePath("uuid-item-dst")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let poisoned = try mutatePayload(data) { payload in
            var items = payload["noteItems"] as! [[String: Any]]
            items[0]["noteId"] = "垃圾ID"
            payload["noteItems"] = items
        }

        do {
            try await makeRepository(path: target).`import`(data: poisoned, passphrase: nil)
            Issue.record("非法 UUID 清单项 noteId 必须整包拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .malformedEntityID("垃圾ID"))
        }
        #expect(try fullState(target).notes.isEmpty)  // 目标库本来为空:未落一行
    }

    // MARK: - 评审修复(Important):PBKDF2 口令拉伸 + 空口令早拒 + KDF 参数入信封

    @Test func emptyPassphraseRejectedOnBothExportAndImport() async throws {
        let source = makePath("emptypw")
        try await seed(source)
        let repo = try makeRepository(path: source)

        do {
            _ = try await repo.export(passphrase: "")
            Issue.record("空口令必须拒绝,不得以空 IKM 加密")
        } catch let error as NoteRepositoryError {
            #expect(error == .emptyPassphrase)
        }

        // 导入侧同口径:加密信封 + 空口令 → 早拒,不做无谓的 10 万轮推导。
        let data = try await repo.export(passphrase: "真口令")
        do {
            try await makeRepository(path: makePath("emptypw-dst")).`import`(data: data, passphrase: "")
            Issue.record("空口令在导入侧同样必须早拒")
        } catch let error as NoteRepositoryError {
            #expect(error == .emptyPassphrase)
        }
    }

    @Test func unknownKDFAlgorithmRejected() async throws {
        let source = makePath("kdf-src")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: "口令")

        var envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        envelope.kdf?.algorithm = "scrypt"  // 密文未动,仅 KDF 标注被改 → 必须拒推
        let poisoned = try JSONEncoder().encode(envelope)

        do {
            try await makeRepository(path: makePath("kdf-dst")).`import`(data: poisoned, passphrase: "口令")
            Issue.record("未知 KDF 算法必须拒绝")
        } catch let error as NoteRepositoryError {
            #expect(error == .unsupportedKDF("scrypt"))
        }
    }

    /// PBKDF2 已知答案向量(RFC/公开测试向量,SHA-256 族):
    /// 钉死「派生链真的是 PBKDF2-HMAC-SHA256」——信封 kdf 字段只是声明,
    /// 向量才是算法正确性的直接证据(防参数换位/实现漂移)。
    @Test func pbkdf2DerivationMatchesKnownVectors() throws {
        func bytes(_ key: SymmetricKey) -> [UInt8] {
            key.withUnsafeBytes { Array($0) }
        }
        // P="password", S="salt", c=1, dkLen=32
        let c1 = try ExportCrypto.deriveKey(passphrase: "password", salt: Data("salt".utf8), iterations: 1)
        #expect(bytes(c1) == [
            0x12, 0x0f, 0xb6, 0xcf, 0xfc, 0xf8, 0xb3, 0x2c, 0x43, 0xe7, 0x22, 0x52, 0x56, 0xc4, 0xf8, 0x37,
            0xa8, 0x65, 0x48, 0xc9, 0x2c, 0xcc, 0x35, 0x48, 0x08, 0x05, 0x98, 0x7c, 0xb7, 0x0b, 0xe1, 0x7b,
        ])
        // 同输入,c=2
        let c2 = try ExportCrypto.deriveKey(passphrase: "password", salt: Data("salt".utf8), iterations: 2)
        #expect(bytes(c2) == [
            0xae, 0x4d, 0x0c, 0x95, 0xaf, 0x6b, 0x46, 0xd3, 0x2d, 0x0a, 0xdf, 0xf9, 0x28, 0xf0, 0x6d, 0xd0,
            0x2a, 0x30, 0x3f, 0x8e, 0xf3, 0xc2, 0x51, 0xdf, 0xd6, 0xe2, 0xd8, 0x5a, 0x95, 0x47, 0x4c, 0x43,
        ])
    }

    // MARK: - 移交项⑦:unlockedOutfits 导出为解析后的 JSON 数组,不是双重编码

    @Test func unlockedOutfitsExportAsParsedArrayNotDoubleEncoded() async throws {
        let source = makePath("outfits")
        try await seed(source)
        let data = try await makeRepository(path: source).export(passphrase: nil)

        let envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        // payload 明文层断言:数组就是 JSON 数组值;若被双重编码,这里会出现 \"bowtie 转义。
        #expect(envelope.payload.contains("\"unlockedOutfits\":[\"bowtie\",\"crown\"]"))
        #expect(!envelope.payload.contains("\\\"bowtie"))  // 不是「JSON 字符串里再套 JSON」

        let payload = try JSONDecoder().decode(ExportPayload.self, from: Data(envelope.payload.utf8))
        let catState = try #require(payload.growthStates.first { $0.petId == "cat" })
        #expect(catState.unlockedOutfits == ["bowtie", "crown"])  // 字段类型就是 [String]
    }
}
