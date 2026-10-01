import Foundation

// MARK: - 宠物姿势（W6-0）

/// 宠物姿势——决定宠物图的选择和布局位置。
public enum PetPose: String, CaseIterable, Sendable {
    /// 举牌（默认）：双前爪举起便签。
    case holding
    /// 坐姿：便签在旁边。
    case sitting
    /// 开心：完成任务后的庆祝姿势。
    case happy
    /// 睡觉：无活跃便签时的待机姿势。
    case sleeping
}

/// 宠物心情——根据养成状态和交互动态选择。
public enum PetMood: String, CaseIterable, Sendable {
    /// 普通状态。
    case neutral
    /// 刚完成任务（喂食后短暂）。
    case happy
    /// 有逾期任务。
    case worried
}

// MARK: - 宠物资产命名（W6-0）

/// 宠物资产名生成器——映射 (species, pose) → Asset Catalog 图片名。
///
/// 命名规范：`pet-{species}-{pose}`，例如 `pet-cat-holding`。
/// 开发期使用 SF Symbol 占位；真实 PNG 按此命名放入 Asset Catalog 后自动生效。
public enum PetAsset {

    /// Asset Catalog 中的图片名（真实资产就绪后使用）。
    public static func imageName(species: PetSpecies, pose: PetPose) -> String {
        "pet-\(species.rawValue)-\(pose.rawValue)"
    }

    /// 是否有「举牌」姿势的美术资产——哪些物种能举牌是**资产层知识**
    /// （P1-3 收敛点），渲染层不得自带副本（此前 iOS Widget / Live Activity
    /// 各内联一份 cat/corgi 特判）。
    /// Watch 端例外（决策固化，2026-10）：20pt 级小尺寸一律用 front——
    /// 举牌细节在小尺寸下丢失，正面头像更清晰。
    public static func hasHoldingPose(species: PetSpecies) -> Bool {
        switch species {
        case .cat, .corgi: return true
        default: return false
        }
    }

    /// 开发期占位 SF Symbol（每个物种不同图标）。
    public static func placeholderSymbol(species: PetSpecies) -> String {
        switch species {
        case .cat:      return "cat.fill"
        case .graycat:  return "cat.fill"
        case .corgi:    return "dog.fill"
        case .shiba:    return "dog.fill"
        case .rabbit:   return "hare.fill"
        case .hamster:  return "leaf.fill"
        }
    }

    /// 宠物的主题色（用于占位渲染和 UI 点缀）。
    public static func accentHue(species: PetSpecies) -> Double {
        switch species {
        case .cat:      return 30    // 橘色
        case .graycat:  return 210   // 蓝灰
        case .corgi:    return 35    // 暖橙
        case .shiba:    return 25    // 红橙
        case .rabbit:   return 330   // 粉色
        case .hamster:  return 40    // 黄橙
        }
    }

    /// 宠物显示名（英文，i18n 就绪）。
    public static func displayName(species: PetSpecies) -> String {
        switch species {
        case .cat:      return "Tabby"
        case .graycat:  return "Misty"
        case .corgi:    return "Biscuit"
        case .shiba:    return "Mochi"
        case .rabbit:   return "Bun"
        case .hamster:  return "Nugget"
        }
    }
}
