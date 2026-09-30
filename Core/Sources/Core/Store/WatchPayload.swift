import Foundation

/// iPhone → Watch 同步有效载荷——经 WatchConnectivity applicationContext 传输。
///
/// 设计原则（D6 架构决定）：
/// - Watch 端为**只读镜像**，不写回 iPhone
/// - applicationContext 大小上限 ~64KB，便签快照远够用
/// - 整体快照（非增量）：每次同步携带全部便签 + 宠物 + 清单项
/// - Watch Widget 读取此结构的 JSON 编码值
public struct WatchPayload: Codable, Sendable, Equatable {
    /// 全部便签快照（按 position 排序）。
    public let notes: [NoteSnapshot]
    /// 当前选中宠物（nil = 未选宠物）。
    public let selectedPet: PetSnapshot?
    /// 同步时间戳。
    public let syncDate: Date

    public init(notes: [NoteSnapshot], selectedPet: PetSnapshot?, syncDate: Date = .now) {
        self.notes = notes
        self.selectedPet = selectedPet
        self.syncDate = syncDate
    }

    // MARK: - 便签快照

    public struct NoteSnapshot: Codable, Sendable, Equatable {
        public let id: String
        public let text: String
        public let done: Bool
        public let dueDate: Date?
        public let style: String?
        public let items: [ItemSnapshot]

        public init(id: String, text: String, done: Bool, dueDate: Date?,
                    style: String?, items: [ItemSnapshot]) {
            self.id = id
            self.text = text
            self.done = done
            self.dueDate = dueDate
            self.style = style
            self.items = items
        }
    }

    // MARK: - 清单项快照

    public struct ItemSnapshot: Codable, Sendable, Equatable {
        public let text: String
        public let done: Bool

        public init(text: String, done: Bool) {
            self.text = text
            self.done = done
        }
    }

    // MARK: - 宠物快照

    public struct PetSnapshot: Codable, Sendable, Equatable {
        public let species: String
        public let displayName: String

        public init(species: String, displayName: String) {
            self.species = species
            self.displayName = displayName
        }
    }

    // MARK: - 序列化

    /// JSON 编码为 applicationContext 字典值。
    public func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return ["watchPayload": json]
    }

    /// 从 applicationContext 字典解码。
    public static func from(context: [String: Any]) -> WatchPayload? {
        guard let json = context["watchPayload"],
              let data = try? JSONSerialization.data(withJSONObject: json)
        else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    // MARK: - 从 SharedStore 构建

    /// 从 App Group 数据库构建当前快照。
    public static func fromStore(_ store: SharedStore) -> WatchPayload {
        let notes = (try? store.allNotes()) ?? []
        let pet = try? store.selectedPet()

        let snapshots = notes.map { note in
            let items = (try? store.noteItems(noteId: note.id)) ?? []
            return NoteSnapshot(
                id: note.id.uuidString,
                text: note.text,
                done: note.done,
                dueDate: note.dueDate,
                style: note.style,
                items: items.map { .init(text: $0.text, done: $0.done) }
            )
        }

        let petSnapshot = pet.map {
            PetSnapshot(
                species: $0.species.rawValue,
                displayName: PetAsset.displayName(species: $0.species)
            )
        }

        return WatchPayload(notes: snapshots, selectedPet: petSnapshot)
    }
}
