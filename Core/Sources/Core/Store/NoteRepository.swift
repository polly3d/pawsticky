import Foundation
import GRDB

// MARK: - NoteRepository(W2-4):App 实际调用的数据门面(plan §1.1)
//
// 职责:①包装 `SharedStore`,以「变更 + 历史**同一写事务**」的口径提供全部变更操作
// ——历史与变更同生共死,是「零丢数据」信任功能的正确性根基;②导出/导入(可选口令
// 加密);③从 HistoryLog 回滚任意变更。
//
// 分层纪律:排序/勾选等**语义**在 NoteEngine(纯逻辑),原子读-改-写在 SharedStore
// (如 `toggleNoteItem` 的事务本体),本层只做编排,不私有一份语义副本。

/// NoteRepository 专属错误(全部 typed,拒绝静默降级)。
public enum NoteRepositoryError: Error, Equatable, Sendable {
    /// 便签不存在(updateNote/deleteNote 的目标行缺失——更新不做静默插入)。
    case noteNotFound(UUID)
    /// 指定的历史条目不存在,或与 (entityType, entityId) 不匹配。
    case historyEntryNotFound(entityType: HistoryEntityType, entityId: String, historyEntryId: UUID)
    /// 恢复需要父实体(清单项→便签、养成态→宠物),但父实体已不存在。
    /// restore 不静默复活父行——父行有自己的历史条目,先恢复父行是显式路径。
    case restoreParentMissing(parentType: HistoryEntityType, parentId: String)
    /// history_log.payload 不是合法 JSON 或字段损坏(防御性,正常写入不可能)。
    case corruptHistoryPayload(String)
    /// 快照 JSON 编码失败(产出侧故障,理论不可达;与读入侧损坏分开报)。
    case snapshotEncodingFailed
    /// 顶层不是合法的导出信封 JSON。
    case malformedEnvelope
    /// format 不是 "pawit.export"。
    case unsupportedFormat(String)
    /// version 不是本实现支持的版本(当前仅 v1;语义即 `!= 1`,
    /// 未来支持多版本读入时收窄为「高于实现」)。
    case unsupportedVersion(Int)
    /// 解密失败(口令错误或密文被篡改;统一报错,不区分两者以防探测)。
    case decryptionFailed
    /// 加密侧故障(PBKDF2 派生失败/nonce 缺失,理论不可达)。
    case encryptionFailed
    /// 信封是加密的但未提供口令。
    case passphraseRequired
    /// 信封是明文的但提供了口令(口径错配,直接拒绝而非猜测)。
    case unexpectedPassphrase
    /// 空口令——空 IKM 会给出「看似成功」的零强度加密,两侧 API 均早拒。
    case emptyPassphrase
    /// 信封声明的 KDF 算法本实现不支持(拒绝按错误参数推导)。
    case unsupportedKDF(String)
    /// payload 不是合法的导出数据体 JSON。
    case malformedPayload
    /// 导入数据含未知的宠物 species(整包拒绝)。
    case unknownSpecies(String)
    /// 导入数据的 UUID 字段(便签 id/清单项 id/noteId)不是合法 UUID 文本
    /// (评审修复:typed 拒绝,绝不静默重铸新 id 改写数据)。
    case malformedEntityID(String)
    /// 清单项指向导入集中不存在的便签(整包拒绝)。
    case orphanedNoteItem(noteId: String)
    /// 养成状态指向导入集中不存在的宠物(整包拒绝)。
    case growthStateWithoutPet(petId: String)
    /// 导入集中出现重复实体 id(整包拒绝)。
    case duplicateEntityInImport(String)
    /// 库内 unlockedOutfits 原文不是合法 JSON 数组(防御性)。
    case corruptUnlockedOutfits(String)
}

public struct NoteRepository: Sendable {

    private let store: SharedStore

    /// 注入式构造(测试/多容器场景)。
    public init(store: SharedStore) {
        self.store = store
    }

    /// 生产入口:进程级单池(W2-1 评审项 1/3 纪律,失败零缓存由 SharedStore 保证)。
    public static func cachedAppGroup() -> NoteRepository? {
        SharedStore.cachedAppGroup().map(NoteRepository.init)
    }

    // MARK: - Note

    /// 创建便签(正文 + 可选到期日),并落一条「创建」后像快照。
    /// - Returns: 已持久化的便签(id 自动生成,position 0,createdAt 当前时刻)。
    ///   注意:返回值为**内存新值**,其 createdAt 亚毫秒精度不会被 GRDB 毫秒文本编码
    ///   保留——与库内行做全等比较时,以读回值(`allNotes()` 等)为基准。
    @discardableResult
    public func createNote(text: String, dueDate: Date? = nil) async throws -> Note {
        let note = Note(text: text, dueDate: dueDate)
        try await store.write { db in
            try note.insert(db)
            try HistoryLog.append(
                in: db, entityType: .note, entityId: note.id.uuidString,
                payload: try PayloadCodec.encode(note)
            )
        }
        return note
    }

    /// 更新便签(整行按传入值落库)。目标行不存在时抛错——**更新不做静默插入**,
    /// 否则陈旧对象会把误删数据「复活」成丢失编辑的状态。
    /// 历史落 **PRE-change 前像**:恢复该条目即回到更新前状态。
    public func updateNote(_ note: Note) async throws {
        try await store.write { db in
            guard let current = try Note.fetchOne(db, key: note.id.uuidString) else {
                throw NoteRepositoryError.noteNotFound(note.id)
            }
            try HistoryLog.append(
                in: db, entityType: .note, entityId: note.id.uuidString,
                payload: try PayloadCodec.encode(current)
            )
            try note.update(db)
        }
    }

    /// 删除便签。级联清单项(W2-1 schema 行为)与历史的关系:
    /// **先**为便签及其全部清单项各落一条删除前像,**再**删除——误删后
    /// `restore` 便签可找回正文,`restore` 各清单项可逐条找回(先父后子)。
    public func deleteNote(id: UUID) async throws {
        try await store.write { db in
            guard let note = try Note.fetchOne(db, key: id.uuidString) else {
                throw NoteRepositoryError.noteNotFound(id)
            }
            let items = try NoteItem
                .filter(Column("noteId") == id.uuidString)
                .order(Column("position").asc, Column("id").asc)
                .fetchAll(db)
            try HistoryLog.append(
                in: db, entityType: .note, entityId: id.uuidString,
                payload: try PayloadCodec.encode(note)
            )
            for item in items {
                try HistoryLog.append(
                    in: db, entityType: .noteItem, entityId: item.id.uuidString,
                    payload: try PayloadCodec.encode(item)
                )
            }
            _ = try Note.deleteOne(db, key: id.uuidString)  // note_item 由外键级联清空
        }
    }

    // MARK: - NoteItem

    /// 新增清单项(父便签必须存在),并落「创建」后像快照。
    /// - Returns: 内存新值(createdAt 亚毫秒精度,库内为毫秒截断)——全等比较以读回值为基准。
    @discardableResult
    public func addItem(to noteId: UUID, text: String) async throws -> NoteItem {
        let item = NoteItem(noteId: noteId, text: text)
        try await store.write { db in
            guard try Note.exists(db, key: noteId.uuidString) else {
                throw NoteRepositoryError.noteNotFound(noteId)
            }
            try item.insert(db)
            try HistoryLog.append(
                in: db, entityType: .noteItem, entityId: item.id.uuidString,
                payload: try PayloadCodec.encode(item)
            )
        }
        return item
    }

    /// 原子翻转清单项勾选:委托 `SharedStore.toggleNoteItem` 的单事务读-改-写本体
    /// (与 Widget intent 同一实现,**禁止** upsert 式翻转),并在同一事务内落翻转前像。
    @discardableResult
    public func toggleItem(noteId: UUID, itemId: UUID) async throws -> Bool {
        try await store.write { db in
            guard let current = try NoteItem
                .filter(Column("id") == itemId.uuidString)
                .filter(Column("noteId") == noteId.uuidString)
                .fetchOne(db)
            else {
                throw SharedStoreError.noteItemNotFound(noteId: noteId, itemId: itemId)
            }
            try HistoryLog.append(
                in: db, entityType: .noteItem, entityId: itemId.uuidString,
                payload: try PayloadCodec.encode(current)
            )
            return try SharedStore.toggleNoteItem(db: db, noteId: noteId, itemId: itemId)
        }
    }

    /// 删除清单项,落删除前像。
    public func deleteItem(noteId: UUID, itemId: UUID) async throws {
        try await store.write { db in
            guard let item = try NoteItem
                .filter(Column("id") == itemId.uuidString)
                .filter(Column("noteId") == noteId.uuidString)
                .fetchOne(db)
            else {
                throw SharedStoreError.noteItemNotFound(noteId: noteId, itemId: itemId)
            }
            try HistoryLog.append(
                in: db, entityType: .noteItem, entityId: itemId.uuidString,
                payload: try PayloadCodec.encode(item)
            )
            _ = try item.delete(db)
        }
    }

    // MARK: - 恢复

    /// 从指定历史条目恢复实体到快照时刻的状态:
    /// * 行已存在 → 覆盖更新(先落当前状态的前像,恢复动作本身入审计链);
    /// * 行不存在 → 重新插入(落「创建」后像,与创建类变更同口径);
    /// * 清单项/养成状态的父实体(便签/宠物)已删除 → 抛 `restoreParentMissing`,
    ///   **不静默复活父行**——父行有自己的历史条目,先恢复父行再恢复子行。
    public func restore(
        entityType: HistoryEntityType,
        entityId: String,
        historyEntryId: UUID
    ) async throws {
        try await store.write { db in
            guard let entry = try HistoryEntry.fetchOne(db, key: historyEntryId.uuidString),
                  entry.entityType == entityType, entry.entityId == entityId else {
                throw NoteRepositoryError.historyEntryNotFound(
                    entityType: entityType, entityId: entityId, historyEntryId: historyEntryId
                )
            }
            switch entityType {
            case .note:
                let restored = try PayloadCodec.decode(ExportNote.self, from: entry.payload).asRow
                if let current = try Note.fetchOne(db, key: restored.id.uuidString) {
                    try HistoryLog.append(
                        in: db, entityType: .note, entityId: entityId,
                        payload: try PayloadCodec.encode(current)
                    )
                    try restored.update(db)
                } else {
                    try restored.insert(db)
                    try HistoryLog.append(
                        in: db, entityType: .note, entityId: entityId,
                        payload: try PayloadCodec.encode(restored)
                    )
                }
            case .noteItem:
                let restored = try PayloadCodec.decode(ExportNoteItem.self, from: entry.payload).asRow
                guard try Note.exists(db, key: restored.noteId.uuidString) else {
                    throw NoteRepositoryError.restoreParentMissing(parentType: .note, parentId: restored.noteId.uuidString)
                }
                if let current = try NoteItem.fetchOne(db, key: restored.id.uuidString) {
                    try HistoryLog.append(
                        in: db, entityType: .noteItem, entityId: entityId,
                        payload: try PayloadCodec.encode(current)
                    )
                    try restored.update(db)
                } else {
                    try restored.insert(db)
                    try HistoryLog.append(
                        in: db, entityType: .noteItem, entityId: entityId,
                        payload: try PayloadCodec.encode(restored)
                    )
                }
            case .petProfile:
                let dto = try PayloadCodec.decode(ExportPetProfile.self, from: entry.payload)
                guard let species = PetSpecies(rawValue: dto.species) else {
                    throw NoteRepositoryError.corruptHistoryPayload(entry.payload)
                }
                let restored = PetProfile(
                    id: dto.id, species: species, displayName: dto.displayName,
                    isSelected: dto.isSelected, acquiredAt: dto.acquiredAt
                )
                if let current = try PetProfile.fetchOne(db, key: restored.id) {
                    try HistoryLog.append(
                        in: db, entityType: .petProfile, entityId: entityId,
                        payload: try PayloadCodec.encode(current)
                    )
                    try restored.update(db)
                } else {
                    try restored.insert(db)
                    try HistoryLog.append(
                        in: db, entityType: .petProfile, entityId: entityId,
                        payload: try PayloadCodec.encode(restored)
                    )
                }
            case .growthState:
                let restored = try PayloadCodec.decode(ExportGrowthState.self, from: entry.payload).asRow
                guard try PetProfile.exists(db, key: restored.petId) else {
                    throw NoteRepositoryError.restoreParentMissing(
                        parentType: .petProfile, parentId: restored.petId
                    )
                }
                if let current = try GrowthState.fetchOne(db, key: restored.petId) {
                    try HistoryLog.append(
                        in: db, entityType: .growthState, entityId: entityId,
                        payload: try PayloadCodec.encode(current)
                    )
                    try restored.update(db)
                } else {
                    try restored.insert(db)
                    try HistoryLog.append(
                        in: db, entityType: .growthState, entityId: entityId,
                        payload: try PayloadCodec.encode(restored)
                    )
                }
            }
        }
    }

    // MARK: - 历史

    /// 某实体的在窗历史(7 天),最新在前。
    public func history(entityType: HistoryEntityType, entityId: String) throws -> [HistoryEntry] {
        try store.read { db in
            try HistoryLog.entries(entityType: entityType, entityId: entityId, in: db)
        }
    }

    // MARK: - 导出 / 导入

    /// 导出全部数据。无口令 → 明文 JSON;有口令 → AES-GCM 加密(随机盐 + PBKDF2
    /// 参数入信封)。空口令早拒(`emptyPassphrase`)——空 IKM 会给出「看似成功」
    /// 的零强度加密。
    /// 导出顺序经引擎排序(`NoteEngine.sortedNotes`/`sortedItems`,与 store SQL 同序契约):
    /// **明文导出**对同一数据字节级稳定;密文导出含随机盐/nonce,不保证字节稳定。
    public func export(passphrase: String?) async throws -> Data {
        if let passphrase, passphrase.isEmpty {
            throw NoteRepositoryError.emptyPassphrase
        }
        let payload: ExportPayload = try store.read { db in
            let notes = NoteEngine.sortedNotes(try Note.fetchAll(db))
            var items: [NoteItem] = []
            items.reserveCapacity(notes.count * 2)
            for note in notes {
                let noteItems = try NoteItem
                    .filter(Column("noteId") == note.id.uuidString)
                    .fetchAll(db)
                items.append(contentsOf: NoteEngine.sortedItems(noteItems))
            }
            let pets = try PetProfile.order(Column("id").asc).fetchAll(db)
            let states = try GrowthState.order(Column("petId").asc).fetchAll(db)
            return ExportPayload(
                notes: notes.map(ExportNote.init),
                noteItems: items.map(ExportNoteItem.init),
                petProfiles: pets.map(ExportPetProfile.init),
                growthStates: try states.map(ExportGrowthState.init)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        if let passphrase {
            let salt = ExportCrypto.randomSalt()
            let sealed = try ExportCrypto.seal(payloadData, passphrase: passphrase, salt: salt)
            let envelope = ExportEnvelope(
                format: Self.exportFormat,
                version: Self.exportVersion,
                salt: salt.base64EncodedString(),
                kdf: ExportKDFParams(
                    algorithm: ExportCrypto.kdfAlgorithmName,
                    iterations: Int(ExportCrypto.kdfIterations)
                ),
                payload: sealed.base64EncodedString()
            )
            return try encoder.encode(envelope)
        }
        let envelope = ExportEnvelope(
            format: Self.exportFormat,
            version: Self.exportVersion,
            salt: nil,
            kdf: nil,
            payload: String(decoding: payloadData, as: UTF8.self)
        )
        return try encoder.encode(envelope)
    }

    /// 导入并 **replace-all**:校验通过后在**单一写事务**内删除现有全部数据并写入导入集。
    ///
    /// 校验(reject-all:任一违规 → 整包拒绝,库零改动):
    /// * 信封格式/版本/加密口径(salt 与口令必须同时有或同时无);
    /// * 未知 species → `unknownSpecies`(与 SharedStore「不静默归一」纪律一致);
    /// * 清单项/养成状态的父实体必须在导入集内 → `orphanedNoteItem`/`growthStateWithoutPet`;
    /// * 重复实体 id → `duplicateEntityInImport`。
    ///
    /// 历史决策:导入事务内**双侧落快照**——被覆盖删除的旧行各留一条删除前像
    /// (坏导入后的回滚依据:若只留导入行的记录,旧数据一旦被替换便无窗可回),
    /// 导入的每一行各留一条「创建」后像。
    ///
    /// 完成后(iOS)对库文件与 WAL 边车**重设文件保护**(移交项⑩):replace-all
    /// 的大量写入会重写/重建 -wal 边车,保护属性需补设。
    public func `import`(data: Data, passphrase: String?) async throws {
        let envelope: ExportEnvelope
        do {
            envelope = try JSONDecoder().decode(ExportEnvelope.self, from: data)
        } catch {
            throw NoteRepositoryError.malformedEnvelope
        }
        guard envelope.format == Self.exportFormat else {
            throw NoteRepositoryError.unsupportedFormat(envelope.format)
        }
        guard envelope.version == Self.exportVersion else {
            throw NoteRepositoryError.unsupportedVersion(envelope.version)
        }

        let payloadData: Data
        switch (envelope.salt, passphrase) {
        case (.some(let saltText), .some(let passphraseText)):
            // 空口令早拒:不做无谓的 10 万轮推导(与导出侧同口径)。
            guard !passphraseText.isEmpty else { throw NoteRepositoryError.emptyPassphrase }
            // KDF 参数必须匹配本实现(评审修复:拒绝按未知算法/缺失参数推导)。
            guard let kdf = envelope.kdf else { throw NoteRepositoryError.malformedEnvelope }
            guard kdf.algorithm == ExportCrypto.kdfAlgorithmName else {
                throw NoteRepositoryError.unsupportedKDF(kdf.algorithm)
            }
            guard kdf.iterations > 0, let salt = Data(base64Encoded: saltText),
                  let combined = Data(base64Encoded: envelope.payload) else {
                throw NoteRepositoryError.malformedEnvelope
            }
            do {
                payloadData = try ExportCrypto.open(
                    combined, passphrase: passphraseText, salt: salt,
                    iterations: UInt32(clamping: kdf.iterations)
                )
            } catch let error as NoteRepositoryError {
                throw error
            } catch {
                throw NoteRepositoryError.decryptionFailed
            }
        case (.none, .none):
            guard !envelope.payload.isEmpty else { throw NoteRepositoryError.malformedEnvelope }
            payloadData = Data(envelope.payload.utf8)
        case (.none, .some):
            throw NoteRepositoryError.unexpectedPassphrase
        case (.some, .none):
            throw NoteRepositoryError.passphraseRequired
        }

        let payload: ExportPayload
        do {
            payload = try JSONDecoder().decode(ExportPayload.self, from: payloadData)
        } catch {
            throw NoteRepositoryError.malformedPayload
        }

        // —— 校验(全部通过才动库;UUID 格式先行,再查引用与重复)——
        for pet in payload.petProfiles where PetSpecies(rawValue: pet.species) == nil {
            throw NoteRepositoryError.unknownSpecies(pet.species)
        }
        // 评审修复:UUID 字段 typed 校验,替代 asRow 里的 `?? UUID()` 静默重铸。
        for note in payload.notes where UUID(uuidString: note.id) == nil {
            throw NoteRepositoryError.malformedEntityID(note.id)
        }
        for item in payload.noteItems {
            if UUID(uuidString: item.id) == nil {
                throw NoteRepositoryError.malformedEntityID(item.id)
            }
            if UUID(uuidString: item.noteId) == nil {
                throw NoteRepositoryError.malformedEntityID(item.noteId)
            }
        }
        let noteIds = Set(payload.notes.map(\.id))
        if noteIds.count != payload.notes.count {
            throw NoteRepositoryError.duplicateEntityInImport("note")
        }
        for item in payload.noteItems where !noteIds.contains(item.noteId) {
            throw NoteRepositoryError.orphanedNoteItem(noteId: item.noteId)
        }
        let itemIds = Set(payload.noteItems.map(\.id))
        if itemIds.count != payload.noteItems.count {
            throw NoteRepositoryError.duplicateEntityInImport("noteItem")
        }
        let petIds = Set(payload.petProfiles.map(\.id))
        if petIds.count != payload.petProfiles.count {
            throw NoteRepositoryError.duplicateEntityInImport("petProfile")
        }
        for state in payload.growthStates where !petIds.contains(state.petId) {
            throw NoteRepositoryError.growthStateWithoutPet(petId: state.petId)
        }
        let stateIds = Set(payload.growthStates.map(\.petId))
        if stateIds.count != payload.growthStates.count {
            throw NoteRepositoryError.duplicateEntityInImport("growthState")
        }

        // 以下转换的 throws 分支是校验后的防御兜底(正常流不可达)。
        let notes = try payload.notes.map { try $0.asRow }
        let items = try payload.noteItems.map { try $0.asRow }
        let pets: [PetProfile] = try payload.petProfiles.map { dto in
            guard let species = PetSpecies(rawValue: dto.species) else {
                // 与 restore 的 corrupt-species 同纪律:宁可抛错,不做防御默认值。
                throw NoteRepositoryError.unknownSpecies(dto.species)
            }
            return PetProfile(
                id: dto.id, species: species,
                displayName: dto.displayName, isSelected: dto.isSelected, acquiredAt: dto.acquiredAt
            )
        }
        let states = payload.growthStates.map(\.asRow)

        try await store.write { db in
            // ① 被覆盖的旧行:逐行落删除前像(坏导入回滚的依据)。
            for note in try Note.fetchAll(db) {
                try HistoryLog.append(
                    in: db, entityType: .note, entityId: note.id.uuidString,
                    payload: try PayloadCodec.encode(note)
                )
            }
            for item in try NoteItem.fetchAll(db) {
                try HistoryLog.append(
                    in: db, entityType: .noteItem, entityId: item.id.uuidString,
                    payload: try PayloadCodec.encode(item)
                )
            }
            for pet in try PetProfile.fetchAll(db) {
                try HistoryLog.append(
                    in: db, entityType: .petProfile, entityId: pet.id,
                    payload: try PayloadCodec.encode(pet)
                )
            }
            for state in try GrowthState.fetchAll(db) {
                try HistoryLog.append(
                    in: db, entityType: .growthState, entityId: state.petId,
                    payload: try PayloadCodec.encode(state)
                )
            }
            // ② 清场:FK 依赖序(养成态 → 宠物;清单项 → 便签)。
            try GrowthState.deleteAll(db)
            try PetProfile.deleteAll(db)
            try NoteItem.deleteAll(db)
            try Note.deleteAll(db)
            // ③ 导入集落库:依赖序(便签 → 清单项;宠物 → 养成态),逐行落「创建」后像。
            for note in notes {
                try note.insert(db)
                try HistoryLog.append(
                    in: db, entityType: .note, entityId: note.id.uuidString,
                    payload: try PayloadCodec.encode(note)
                )
            }
            for item in items {
                try item.insert(db)
                try HistoryLog.append(
                    in: db, entityType: .noteItem, entityId: item.id.uuidString,
                    payload: try PayloadCodec.encode(item)
                )
            }
            for pet in pets {
                try pet.insert(db)
                try HistoryLog.append(
                    in: db, entityType: .petProfile, entityId: pet.id,
                    payload: try PayloadCodec.encode(pet)
                )
            }
            for state in states {
                try state.insert(db)
                try HistoryLog.append(
                    in: db, entityType: .growthState, entityId: state.petId,
                    payload: try PayloadCodec.encode(state)
                )
            }
        }

        // 移交项⑩:replace-all 大批量写入会重写 WAL 边车,补设文件保护(iOS)。
        #if os(iOS)
        store.reapplyFileProtection()
        #endif
    }

    /// 导出格式标识与版本常量(信封校验基准)。
    static let exportFormat = "pawit.export"
    static let exportVersion = 1
}
