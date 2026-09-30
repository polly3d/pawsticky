import Foundation
import GRDB

/// 首发六只宠物(与 `art/characters/` 目录一一对应);rawValue 即 note 表的存储值。
public enum PetSpecies: String, Equatable, Sendable, CaseIterable {
    case cat
    /// 灰白猫。
    case graycat
    case corgi
    case shiba
    case rabbit
    case hamster
}

/// 一只宠物档案,对应 pet_profile 表(W2 新增)。
/// `isSelected` 标记「当前举牌宠物」;多选中的裁决属引擎语义(W2-3/W6),
/// 本层只做存储——`SharedStore.selectedPet()` 以 id ASC 决胜保证读侧确定性。
public struct PetProfile: Equatable, Sendable, FetchableRecord, PersistableRecord {
    /// 数据库表名(GRDB)。
    public static let databaseTableName = "pet_profile"

    /// 稳定标识(首发六宠即 species rawValue;W9 生成宠物可用任意字符串)。
    public let id: String
    public var species: PetSpecies
    public var displayName: String
    /// 是否为「当前选中」宠物。
    public var isSelected: Bool
    public var acquiredAt: Date

    public init(
        id: String,
        species: PetSpecies,
        displayName: String,
        isSelected: Bool = false,
        acquiredAt: Date = .now
    ) {
        self.id = id
        self.species = species
        self.displayName = displayName
        self.isSelected = isSelected
        self.acquiredAt = acquiredAt
    }
}

extension PetProfile {
    /// GRDB 手工列映射:species 以 rawValue TEXT 持久化;未知值显式抛错(不静默归一)。
    public init(row: Row) throws {
        let rawSpecies: String = row["species"]
        guard let species = PetSpecies(rawValue: rawSpecies) else {
            throw SharedStoreError.corruptPetSpecies(rawSpecies)
        }
        id = row["id"]
        self.species = species
        displayName = row["displayName"]
        isSelected = row["isSelected"]
        acquiredAt = row["acquiredAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["species"] = species.rawValue
        container["displayName"] = displayName
        container["isSelected"] = isSelected
        container["acquiredAt"] = acquiredAt
    }
}
