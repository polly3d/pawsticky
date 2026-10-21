import UIKit

/// C9：`LiveActivityManager.pin` 的失败模式——Live Activities 被系统关闭
/// （用户在锁屏移除时顺带关掉、或系统设置里关掉、或低电量模式短暂禁用）。
/// 公开 API 无法区分这些原因，文案统一指向 iPhone 设置。
enum LiveActivityUnavailableError: Error, Equatable {
    case activitiesDisabled
}

/// Pin 失败的用户呈现决策：弹窗文案 + 是否给"去系统设置"的入口。
/// 便签列表把它渲染成 alert（C9 修法：失败弹窗 + 设置页状态行）。
enum PinIssue: Equatable, Identifiable {
    /// Live Activities 被系统关闭——可以指路系统设置。
    case liveActivitiesDisabled
    /// 其他失败（如系统并发上限）——只告知重试。
    case pinFailed

    var id: Self { self }

    /// 从 pin 抛出的任意错误归因：typed error → 指路系统设置；其余 → 通用重试。
    static func issue(for error: Error) -> PinIssue {
        (error as? LiveActivityUnavailableError) != nil ? .liveActivitiesDisabled : .pinFailed
    }

    var alertTitle: String {
        switch self {
        case .liveActivitiesDisabled: "Live Activities Are Off"
        case .pinFailed: "Couldn't Pin Note"
        }
    }

    var alertMessage: String {
        switch self {
        case .liveActivitiesDisabled:
            "To pin notes to your Lock Screen, allow Live Activities for PawSticky in iPhone Settings."
        case .pinFailed:
            "Please try again."
        }
    }

    var showsSettingsShortcut: Bool { self == .liveActivitiesDisabled }
}

/// 设置页 Live Activities 状态行的取值——注入 bool 以便测试钉住 On / Off 词汇
/// （将来接 Localizable.strings 时两处共用同一组键）。
enum LiveActivityStatusText {
    static func text(activitiesEnabled: Bool) -> String {
        activitiesEnabled ? "On" : "Off"
    }
}

/// 打开本 App 的系统设置页（设置 → PawSticky，Live Activities 开关就在那里）。
/// 全 App 唯一的 `openSettingsURLString` 出口。
@MainActor
enum SystemSettings {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
