import Foundation

/// 设置页 “About” 用到的 App 自身信息。
enum AppInfo {

    /// 版本文案：`"1.0 (1)"`；只有版本号时是 `"1.0"`；取不到时是 `"Unknown"`。
    ///
    /// `info` 默认取当前进程的 Info.plist（版本号来自 project.yml 的 MARKETING_VERSION /
    /// CURRENT_PROJECT_VERSION，由 XcodeGen 生成的 Info.plist 用 `$(…)` 引用）；
    /// 参数化只是为了让测试不依赖宿主 App 的真实版本。
    static func versionDescription(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        guard let short = info?["CFBundleShortVersionString"] as? String, !short.isEmpty else {
            return "Unknown"
        }
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }
}
