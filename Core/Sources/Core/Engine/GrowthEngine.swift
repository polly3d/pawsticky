import Foundation

// MARK: - Outfit（W7-1）

/// 12 件装扮——按 fedLevel 阈值逐步解锁。
///
/// rawValue 存入 GrowthState.unlockedOutfits JSON 数组。
/// 商业计划 §4.2：12 件 = 可感知的收集节奏 × 不至于无限膨胀。
public enum Outfit: String, CaseIterable, Codable, Sendable {
    case bowtie         // 🎀 蝴蝶结
    case topHat         // 🎩 礼帽
    case crown          // 👑 皇冠
    case scarf          // 🧣 围巾
    case sunglasses     // 🕶️ 墨镜
    case flowerWreath   // 🌸 花环
    case cape           // 🦸 斗篷
    case partyHat       // 🎉 派对帽
    case bandana        // 🏴 头巾
    case wings          // 🪽 翅膀
    case halo           // 😇 光环
    case spaceHelmet    // 🚀 太空帽
}

extension Outfit {
    /// 解锁所需的 fedLevel 阈值（从 5 开始，每 5 级解锁一件）。
    public var unlockThreshold: Int {
        guard let index = Self.allCases.firstIndex(of: self) else { return Int.max }
        return (index + 1) * 5
    }

    /// 显示名（英文，i18n 就绪）。
    public var displayName: String {
        switch self {
        case .bowtie:       return "Bowtie"
        case .topHat:       return "Top Hat"
        case .crown:        return "Crown"
        case .scarf:        return "Scarf"
        case .sunglasses:   return "Sunglasses"
        case .flowerWreath: return "Flower Wreath"
        case .cape:         return "Cape"
        case .partyHat:     return "Party Hat"
        case .bandana:      return "Bandana"
        case .wings:        return "Wings"
        case .halo:         return "Halo"
        case .spaceHelmet:  return "Space Helmet"
        }
    }

    /// 装扮图标 SF Symbol（占位；真实资产后替换）。
    public var symbolName: String {
        switch self {
        case .bowtie:       return "gift"
        case .topHat:       return "theatermask.and.paintbrush"
        case .crown:        return "crown"
        case .scarf:        return "wind"
        case .sunglasses:   return "eyeglasses"
        case .flowerWreath: return "leaf.circle"
        case .cape:         return "bolt.shield"
        case .partyHat:     return "party.popper"
        case .bandana:      return "flag"
        case .wings:        return "bird"
        case .halo:         return "sparkles"
        case .spaceHelmet:  return "globe.americas"
        }
    }
}

// MARK: - GrowthEngine（W7-0）
//
// 轻养成逻辑：纯函数、无 DB 依赖、日历注入。
// 输入 (GrowthState, now, calendar) → 输出 (GrowthState)。
// 与 NoteEngine 同一架构原则。

/// 轻养成引擎（全部纯函数；状态只存在于入参）。
public enum GrowthEngine {

    /// 喂食——完成一次任务后调用。
    ///
    /// 规则：
    /// - fedLevel += 1（永增不减，断签不惩罚）
    /// - 若「今天」与 lastActiveDay 是同一本地日 → streak 不变（防一天多次喂食刷连击）
    /// - 若「今天」是 lastActiveDay 的下一个本地日 → streak += 1（连击续上）
    /// - 否则（隔了 ≥2 天）→ streak 归 1（新连击周期开始，不惩罚 fedLevel）
    /// - lastActiveDay 更新为 now
    /// - 检查新解锁的装扮，追加到 unlockedOutfits
    public static func feed(
        state: GrowthState,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GrowthState {
        var next = state
        next.fedLevel += 1
        next.lastActiveDay = now

        // 连击计算
        if let lastActive = state.lastActiveDay {
            let planner = TimelinePlanner(calendar: calendar)
            if planner.isSameDay(lastActive, now) {
                // 同一天再次喂食，streak 不变
            } else if isConsecutiveDay(lastActive, now, calendar: calendar) {
                next.streakDays += 1
            } else {
                // 断签：streak 归 1（今天算第一天），fedLevel 不减
                next.streakDays = 1
            }
        } else {
            // 首次喂食
            next.streakDays = 1
        }

        // 检查装扮解锁
        let currentOutfits = parseOutfits(next.unlockedOutfits)
        var updatedOutfits = currentOutfits
        for outfit in Outfit.allCases where outfit.unlockThreshold <= next.fedLevel {
            if !updatedOutfits.contains(outfit) {
                updatedOutfits.append(outfit)
            }
        }
        if updatedOutfits.count != currentOutfits.count {
            next.unlockedOutfits = encodeOutfits(updatedOutfits)
        }

        return next
    }

    /// 当前已解锁的装扮列表。
    public static func unlockedOutfits(state: GrowthState) -> [Outfit] {
        parseOutfits(state.unlockedOutfits)
    }

    /// 下一件待解锁的装扮（如果有的话）。
    public static func nextOutfit(state: GrowthState) -> (outfit: Outfit, remaining: Int)? {
        let unlocked = Set(parseOutfits(state.unlockedOutfits))
        for outfit in Outfit.allCases where !unlocked.contains(outfit) {
            let remaining = outfit.unlockThreshold - state.fedLevel
            if remaining > 0 {
                return (outfit, remaining)
            }
        }
        return nil
    }

    /// 喂食等级的进度百分比（到下一个解锁阈值）。
    public static func progressToNextOutfit(state: GrowthState) -> Double {
        guard let next = nextOutfit(state: state) else { return 1.0 }
        let prevThreshold = Outfit.allCases
            .filter { $0.unlockThreshold <= state.fedLevel }
            .map(\.unlockThreshold)
            .max() ?? 0
        let range = next.outfit.unlockThreshold - prevThreshold
        guard range > 0 else { return 1.0 }
        let progress = state.fedLevel - prevThreshold
        return Double(progress) / Double(range)
    }

    /// 是否所有装扮都已解锁。
    public static func isFullyUnlocked(state: GrowthState) -> Bool {
        parseOutfits(state.unlockedOutfits).count >= Outfit.allCases.count
    }

    // MARK: - Private Helpers

    /// 判断 b 是否是 a 的「下一个本地日」。
    private static func isConsecutiveDay(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: a) else { return false }
        let planner = TimelinePlanner(calendar: calendar)
        return planner.isSameDay(nextDay, b)
    }

    /// 解析 JSON 字符串为装扮数组。
    static func parseOutfits(_ json: String) -> [Outfit] {
        guard let data = json.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return rawValues.compactMap { Outfit(rawValue: $0) }
    }

    /// 编码装扮数组为 JSON 字符串。
    static func encodeOutfits(_ outfits: [Outfit]) -> String {
        let rawValues = outfits.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(rawValues),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}
