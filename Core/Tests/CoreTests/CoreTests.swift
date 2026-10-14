import Foundation
import Testing
@testable import Core

struct CoreTests {
    @Test func smoke() {
        #expect(PawItInfo.appGroupID == "group.com.fitpetgo.pawsticky.shared")
    }

    /// 隐私政策 / 支持页 URL：审核指南 5.1.1(i) 要求 App 内可达。
    /// 写成 http、裸域名或漏掉 host 的低级错误应当在测试里就失败，而不是等审核员点进去。
    @Test func legalURLsAreHTTPSLinksToConcretePages() {
        for url in [PawItInfo.privacyPolicyURL, PawItInfo.supportURL] {
            #expect(url.scheme == "https", "\(url) 必须是 https")
            #expect(!(url.host ?? "").isEmpty, "\(url) 缺 host")
            #expect(url.path.count > 1, "\(url) 不能是裸域名——点进去应落在具体页面")
        }
        #expect(PawItInfo.privacyPolicyURL != PawItInfo.supportURL, "隐私政策与支持页不应是同一个 URL")
    }

    @Test func noteEquatable() {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 0)
        #expect(
            Note(id: id, text: "喂食", createdAt: createdAt)
                == Note(id: id, text: "喂食", createdAt: createdAt)
        )
    }
}
