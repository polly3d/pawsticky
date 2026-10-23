import Testing
import Core
@testable import PawIt

/// W2 卡:宿主链接(- target: PawIt)后的最小接线验证——不测 UI 行为,
/// 只钉住「App 层类型可从测试进程实例化」,保持链接真实有效(防挂空依赖)。
struct PawItTests {
    @Test func smoke() {
        #expect(PawItInfo.appGroupID == "group.com.fitpetgo.pawsticky.shared")
    }

    // `PawItApp.init()` 是 @MainActor（继承自 App 协议）：测试也放到主 actor 上跑，
    // 既消除编译器的隔离警告，也让 App 入口在它真实运行的上下文里被构造。
    @MainActor
    @Test func appEntryTypesInstantiateUnderTestHost() {
        // 编辑器根视图与 @main App 入口均可实例化:编译期绑定 + 运行期构造皆通。
        _ = ContentView()
        _ = PawItApp()
    }
}
