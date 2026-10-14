import Testing
@testable import PawIt

/// 设置页“Version”一行的文案逻辑。审核员和用户报问题时都会看这一行，所以版本 / 构建号必须真的取到。
struct AppInfoTests {

    @Test func versionDescriptionCombinesShortVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"]
        #expect(AppInfo.versionDescription(info: info) == "1.2 (7)")
    }

    @Test func versionDescriptionDegradesGracefullyWhenKeysAreMissing() {
        #expect(AppInfo.versionDescription(info: ["CFBundleShortVersionString": "1.0"]) == "1.0")
        #expect(AppInfo.versionDescription(info: [:]) == "Unknown")
        #expect(AppInfo.versionDescription(info: nil) == "Unknown")
    }

    /// 宿主 App 的 Info.plist 里版本号来自 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`，
    /// 构建后必须已被展开——否则用户会在设置页看到 "$(MARKETING_VERSION)"。
    @Test func runningBundleReportsAnExpandedVersion() {
        let text = AppInfo.versionDescription()
        #expect(text != "Unknown")
        #expect(!text.contains("$("), "版本号变量没有被展开：\(text)")
    }
}
