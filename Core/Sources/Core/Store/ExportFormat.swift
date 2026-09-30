import Foundation
import CryptoKit

// MARK: - 导出/导入格式 v1(W2-4,plan §7-P2 换机协议)
//
// 信封:`{ "format": "pawit.export", "version": 1, "salt": base64-or-null,
//         "payload": <明文 JSON 字符串 | base64 密文> }`
// * 无口令:`payload` = ExportPayload 的明文 JSON 字符串;
// * 有口令:随机 16B 盐入信封,payload = AES-GCM(combined) 的 base64,
//   密钥 = HKDF-SHA256(passphrase, salt, info="pawit.export.v1", 32B)。
// * 日期以 JSON number(1970 秒,double)编码,与 GRDB `.datetime` 毫秒文本
//   毫秒截断规则一致,round-trip 相等成立。

/// 导出信封(顶层 JSON)。
public struct ExportEnvelope: Codable, Equatable, Sendable {
    /// 固定为 "pawit.export";导入时严格校验,陌生格式拒绝。
    public var format: String
    /// 导出格式版本;当前 1。未来升版只能加字段/增版本号,旧版本导入路径保留。
    public var version: Int
    /// AES-GCM 盐(base64);nil = 明文 payload。
    public var salt: String?
    /// 明文 JSON 字符串或 base64 密文(视 salt 而定)。
    public var payload: String

    public init(format: String, version: Int, salt: String?, payload: String) {
        self.format = format
        self.version = version
        self.salt = salt
        self.payload = payload
    }
}

/// 导出数据体(即 `payload` 明文 JSON 的结构)。
public struct ExportPayload: Codable, Equatable, Sendable {
    public var notes: [ExportNote]
    public var noteItems: [ExportNoteItem]
    public var petProfiles: [ExportPetProfile]
    public var growthStates: [ExportGrowthState]

    public init(
        notes: [ExportNote],
        noteItems: [ExportNoteItem],
        petProfiles: [ExportPetProfile],
        growthStates: [ExportGrowthState]
    ) {
        self.notes = notes
        self.noteItems = noteItems
        self.petProfiles = petProfiles
        self.growthStates = growthStates
    }
}

// MARK: - 行级 DTO:存储行 <-> 导出 JSON 的唯一编码路径
//
// 之所以不直接让 Note 等模型 Codable:① 导出是跨版本契约,需要显式的稳定字段集,
// 不应被存储列演化(w3.v1 style 列)被动改动;② GrowthState.unlockedOutfits 是
// 「JSON 数组原文」字符串,直接编码会双重转义(移交项⑦),必须在 DTO 层解析成
// [String] 值再编码。

/// note 表行导出。
public struct ExportNote: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var createdAt: Date
    public var done: Bool
    public var dueDate: Date?
    public var position: Int

    public init(_ note: Note) {
        id = note.id.uuidString
        text = note.text
        createdAt = note.createdAt
        done = note.done
        dueDate = note.dueDate
        position = note.position
    }

    /// 还原为存储行。id 非法文本由调用方校验流程兜底(导出前已校验)。
    public var asRow: Note {
        Note(
            id: UUID(uuidString: id) ?? UUID(),
            text: text, createdAt: createdAt, done: done,
            dueDate: dueDate, position: position
        )
    }
}

/// note_item 表行导出。
public struct ExportNoteItem: Codable, Equatable, Sendable {
    public var id: String
    public var noteId: String
    public var text: String
    public var done: Bool
    public var position: Int
    public var createdAt: Date

    public init(_ item: NoteItem) {
        id = item.id.uuidString
        noteId = item.noteId.uuidString
        text = item.text
        done = item.done
        position = item.position
        createdAt = item.createdAt
    }

    public var asRow: NoteItem {
        NoteItem(
            id: UUID(uuidString: id) ?? UUID(),
            noteId: UUID(uuidString: noteId) ?? UUID(),
            text: text, done: done, position: position, createdAt: createdAt
        )
    }
}

/// pet_profile 表行导出。species 存 rawValue 字符串,导入时按 PetSpecies 校验。
public struct ExportPetProfile: Codable, Equatable, Sendable {
    public var id: String
    public var species: String
    public var displayName: String
    public var isSelected: Bool
    public var acquiredAt: Date

    public init(_ pet: PetProfile) {
        id = pet.id
        species = pet.species.rawValue
        displayName = pet.displayName
        isSelected = pet.isSelected
        acquiredAt = pet.acquiredAt
    }
}

/// growth_state 表行导出。
/// **移交项⑦**:`unlockedOutfits` 在库内是 JSON 数组**字符串**,导出时解析为
/// `[String]` 值编码——避免「JSON 字符串里再套 JSON」的双重转义(人读即懂、
/// 跨语言解析器无需二段解码);导入时再序列化回原文入库。
public struct ExportGrowthState: Codable, Equatable, Sendable {
    public var petId: String
    public var fedLevel: Int
    public var streakDays: Int
    public var lastActiveDay: Date?
    public var unlockedOutfits: [String]

    /// 从存储行构造;`unlockedOutfits` 原文不是合法 JSON 数组视为脏数据,显式抛错
    /// (与 SharedStore 侧「不静默归一」的防御纪律一致)。
    public init(_ state: GrowthState) throws {
        petId = state.petId
        fedLevel = state.fedLevel
        streakDays = state.streakDays
        lastActiveDay = state.lastActiveDay
        guard let data = state.unlockedOutfits.data(using: .utf8),
              let outfits = try? JSONDecoder().decode([String].self, from: data) else {
            throw NoteRepositoryError.corruptUnlockedOutfits(state.unlockedOutfits)
        }
        unlockedOutfits = outfits
    }

    /// 序列化回存储行(unlockedOutfits 恢复为 JSON 数组原文)。
    public var asRow: GrowthState {
        let data = (try? JSONEncoder().encode(unlockedOutfits)) ?? Data("[]".utf8)
        return GrowthState(
            petId: petId, fedLevel: fedLevel, streakDays: streakDays,
            lastActiveDay: lastActiveDay,
            unlockedOutfits: String(data: data, encoding: .utf8) ?? "[]"
        )
    }
}

// MARK: - 快照编解码(history_log.payload 与导出共用)

/// payload JSON 编解码工具:统一 sortedKeys 输出(字节级稳定,便于 diff/测试钉子)。
enum PayloadCodec {

    static func encode(_ note: Note) throws -> String {
        try encodedString(ExportNote(note))
    }

    static func encode(_ item: NoteItem) throws -> String {
        try encodedString(ExportNoteItem(item))
    }

    static func encode(_ pet: PetProfile) throws -> String {
        try encodedString(ExportPetProfile(pet))
    }

    static func encode(_ state: GrowthState) throws -> String {
        try encodedString(ExportGrowthState(state))
    }

    /// 解码快照;失败视为日志损坏(防御性,正常写入路径不可能出现)。
    static func decode<T: Decodable>(_ type: T.Type, from payload: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(payload.utf8))
        } catch {
            throw NoteRepositoryError.corruptHistoryPayload(payload)
        }
    }

    private static func encodedString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let string = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw NoteRepositoryError.corruptHistoryPayload("")
        }
        return string
    }
}

// MARK: - 口令加密:AES-GCM + HKDF-SHA256

/// 导出加密原语。CryptoKit 全平台可用(iOS/watchOS,含 watchOS 10 声明目标)。
enum ExportCrypto {

    /// HKDF info 域分离:绑定导出格式版本,防未来协议复用同一口令派生链。
    private static let hkdfInfo = Data("pawit.export.v1".utf8)

    /// 随机盐(16 字节,CryptoKit CSPRNG)。
    static func randomSalt() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }

    /// 口令 -> 256 位 AES 密钥(HKDF-SHA256,盐入信封)。
    static func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(passphrase.utf8)),
            salt: salt,
            info: hkdfInfo,
            outputByteCount: 32
        )
    }

    /// AES-GCM 加密,返回 combined(nonce+ciphertext+tag)原始数据。
    static func seal(_ plaintext: Data, passphrase: String, salt: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: deriveKey(passphrase: passphrase, salt: salt))
        guard let combined = box.combined else {
            throw NoteRepositoryError.decryptionFailed
        }
        return combined
    }

    /// AES-GCM 解密;口令错误/密文被篡改统一抛 `decryptionFailed`(不区分,防探测)。
    static func open(_ combined: Data, passphrase: String, salt: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: deriveKey(passphrase: passphrase, salt: salt))
    }
}
