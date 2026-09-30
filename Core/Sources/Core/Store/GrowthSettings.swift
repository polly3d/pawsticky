import Foundation

/// 养成功能开关（W7-5）——「关闭养成」后隐藏进度/喂食，不影响已有数据。
///
/// 存储位置：App Group UserDefaults（与 WidgetPreferences 同源），
/// 这样 Widget 也能读到此开关状态。
public enum GrowthSettings {

    /// UserDefaults key。
    private static let key = "growthEnabled"

    nonisolated(unsafe) private static let defaults: UserDefaults? = {
        UserDefaults(suiteName: PawItInfo.appGroupID)
    }()

    /// 养成功能是否启用（默认 true）。
    public static var isEnabled: Bool {
        get {
            guard let d = defaults else { return true }
            // 如果 key 不存在，object(forKey:) 返回 nil → 默认启用
            return (d.object(forKey: key) as? Bool) ?? true
        }
        set {
            defaults?.set(newValue, forKey: key)
        }
    }
}
