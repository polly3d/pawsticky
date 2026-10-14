import Testing
import Foundation
import Core
@testable import PawIt

/// 站内跳转在 App 里的落点：URL → 路由器 → 「编辑器该怎么开」。
///
/// 这里守的是两个容易被时序坑到的点：
/// 1. 冷启动时 URL 先于列表页就绪，必须先挂起、等列表页出现后取走（不能丢）；
/// 2. 跳转要尊重现实——便签已被删、或用户正在首次引导中，都不能硬开编辑器。
@MainActor
struct DeepLinkRoutingTests {

    private let noteID = UUID()

    // MARK: - 解析落点（DeepLinkResolver）

    @Test func newNoteOpensTheCreateEditor() {
        let mode = DeepLinkResolver.editorMode(
            for: .newNote, onboardingNeeded: false, noteExists: { _ in false }
        )
        #expect(mode == .create)
    }

    @Test func openingAnExistingNoteOpensItsEditor() {
        let id = noteID
        let mode = DeepLinkResolver.editorMode(
            for: .openNote(id), onboardingNeeded: false, noteExists: { $0 == id }
        )
        #expect(mode == .edit(id))
    }

    @Test func openingADeletedNoteDoesNothing() {
        // 小组件的快照可能比库旧：便签在 App 里已被删。落到列表页即可，不要开一个空编辑器。
        let mode = DeepLinkResolver.editorMode(
            for: .openNote(noteID), onboardingNeeded: false, noteExists: { _ in false }
        )
        #expect(mode == nil)
    }

    @Test func firstLaunchOnboardingWinsOverEveryLink() {
        // 全新安装的人可以在打开 App 之前就从画廊加了小组件、再点空状态。
        // 引导最后本来就会把他带进新建页，此时再弹一个编辑器会和引导全屏页打架。
        for link in [DeepLink.newNote, .openNote(noteID)] {
            let mode = DeepLinkResolver.editorMode(
                for: link, onboardingNeeded: true, noteExists: { _ in true }
            )
            #expect(mode == nil, "\(link)")
        }
    }

    // MARK: - scheme 注册

    /// `DeepLink.scheme`（Core 里）与 `project.yml` 的 `CFBundleURLTypes` 是同一个约定的两半。
    /// 只改一边，`simctl openurl` / Safari / 快捷指令里的链接就打不开 App——
    /// 而小组件点击不依赖注册，所以光点小组件是发现不了的。
    @Test func theSchemeIsRegisteredInTheAppBundle() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(DeepLink.scheme), "Info.plist 没注册 \(DeepLink.scheme)://：\(schemes)")
    }

    // MARK: - 路由器（DeepLinkRouter）

    @Test func routerHoldsAValidLinkUntilTheListTakesIt() {
        let router = DeepLinkRouter()
        #expect(router.pending == nil)

        router.receive(DeepLink.newNote.url)
        #expect(router.pending == .newNote, "冷启动：列表页还没出现，链接先挂起")
    }

    @Test func routerIgnoresForeignOrMalformedURLs() {
        let router = DeepLinkRouter()
        router.receive(URL(string: "https://example.com/new")!)
        router.receive(URL(string: "pawsticky://delete-all")!)
        router.receive(URL(string: "pawsticky://note/not-a-uuid")!)
        #expect(router.pending == nil)
    }

    @Test func garbageDoesNotClobberAPendingLink() {
        let router = DeepLinkRouter()
        router.receive(DeepLink.openNote(noteID).url)
        router.receive(URL(string: "pawsticky://bogus")!)
        #expect(router.pending == .openNote(noteID), "无效 URL 不能把还没处理的有效链接冲掉")
    }

    @Test func theLatestValidLinkWins() {
        let router = DeepLinkRouter()
        router.receive(DeepLink.newNote.url)
        router.receive(DeepLink.openNote(noteID).url)
        #expect(router.pending == .openNote(noteID), "用户最后一次点的才是他想去的地方")
    }
}
