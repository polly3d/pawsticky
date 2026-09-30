import Foundation
import GRDB

/// 一只宠物的轻养成状态,对应 growth_state 表(W2 新增)。
/// 纯存储骨架——喂养进度/连击/解锁逻辑是 W2-3/W7 的引擎职责,本类型不含任何行为。
public struct GrowthState: Equatable, Sendable, FetchableRecord, PersistableRecord, Codable {
    /// 数据库表名(GRDB)。
    public static let databaseTableName = "growth_state"

    /// 所属宠物(pet_profile 外键,ON DELETE CASCADE 级联清理)。
    public var petId: String
    /// 喂食进度(引擎语义见 W2-3/W7;存储层只保真值)。
    public var fedLevel: Int
    /// 连续打卡天数(断签不惩罚——Finch 原则;计算归 W7)。
    public var streakDays: Int
    /// 最近活跃的「日」锚点;nil = 从未活跃。
    /// 存储决策:按任务规格以 `.datetime` 文本存整时刻(Date),「本地日」的
    /// 归一(时区/跨午夜)是 W2-3/W7 引擎写入侧的职责——本层不解析不换算。
    public var lastActiveDay: Date?
    /// 已解锁装扮,JSON 数组字符串(如 `["bowtie","crown"]`);解析归 W2-3/W7,本层只存原文。
    public var unlockedOutfits: String

    public init(
        petId: String,
        fedLevel: Int = 0,
        streakDays: Int = 0,
        lastActiveDay: Date? = nil,
        unlockedOutfits: String = "[]"
    ) {
        self.petId = petId
        self.fedLevel = fedLevel
        self.streakDays = streakDays
        self.lastActiveDay = lastActiveDay
        self.unlockedOutfits = unlockedOutfits
    }
}
