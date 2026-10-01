import SwiftUI

/// 便签颜色预设（W3-1）——存入 note.style 列的 rawValue 即持久化值。
/// nil（数据库 NULL）= classicYellow 默认。6 款预设覆盖便签场景的常见色彩情绪。
public enum NoteStylePreset: String, CaseIterable, Codable, Sendable {
    case classicYellow
    case mint
    case sakura
    case ocean
    case lavender
    case charcoal
}

extension NoteStylePreset {

    /// 持久化 style 原文 → 预设的唯一解析点（P1-3 DRY）。
    /// nil（数据库 NULL）与未知原文一律回退 classicYellow——此前该解析式
    /// 在 App / Widget / 分享卡各处内联重复 7 处。
    public static func resolve(_ rawValue: String?) -> NoteStylePreset {
        rawValue.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }

    /// 便签背景色。
    public var backgroundColor: Color {
        switch self {
        case .classicYellow: return Color(red: 1.0, green: 0.976, blue: 0.769)   // #FFF9C4
        case .mint:          return Color(red: 0.784, green: 0.902, blue: 0.788)  // #C8E6C9
        case .sakura:        return Color(red: 0.984, green: 0.804, blue: 0.863)  // #FBCDDC
        case .ocean:         return Color(red: 0.733, green: 0.871, blue: 0.984)  // #BBDEFB
        case .lavender:      return Color(red: 0.839, green: 0.788, blue: 0.945)  // #D6C9F1
        case .charcoal:      return Color(red: 0.259, green: 0.259, blue: 0.278)  // #424247
        }
    }

    /// 便签正文色（charcoal 用亮色文字，其余用深色）。
    public var textColor: Color {
        switch self {
        case .charcoal: return Color(red: 0.933, green: 0.933, blue: 0.941)  // #EEEEEF
        default:        return Color(red: 0.2, green: 0.2, blue: 0.2)        // #333333
        }
    }

    /// 显示名（英文，i18n 就绪——SwiftUI Text 自动查 Localizable.strings）。
    public var displayName: String {
        switch self {
        case .classicYellow: return "Classic"
        case .mint:          return "Mint"
        case .sakura:        return "Sakura"
        case .ocean:         return "Ocean"
        case .lavender:      return "Lavender"
        case .charcoal:      return "Charcoal"
        }
    }
}
