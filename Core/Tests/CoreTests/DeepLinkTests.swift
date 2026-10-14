import Testing
import Foundation
@testable import Core

/// 站内跳转契约（`pawsticky://…`）的行为钉子。
///
/// 这个 scheme 注册进 Info.plist 之后，网页和其它 App 都能触发它——
/// 所以解析必须是严格白名单：认得的两种形态才放行，其余一律 nil，
/// 而不是「尽量理解」。
struct DeepLinkTests {

    private let noteID = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!

    // MARK: - 构造 URL

    @Test func newNoteURLIsPawstickyNew() {
        #expect(DeepLink.newNote.url.absoluteString == "pawsticky://new")
    }

    @Test func openNoteURLCarriesTheNoteID() {
        #expect(
            DeepLink.openNote(noteID).url.absoluteString
                == "pawsticky://note/1B4E28BA-2FA1-11D2-883F-0016D3CCA427"
        )
    }

    // MARK: - 往返

    @Test func buildThenParseRoundTrips() {
        for link in [DeepLink.newNote, .openNote(noteID), .openNote(UUID())] {
            #expect(DeepLink(url: link.url) == link, "\(link) 经 url 再解析必须还原")
        }
    }

    // MARK: - 宽容的部分（有意为之，各有理由）

    @Test func schemeAndHostIgnoreCase() {
        // URL 的 scheme / host 按规范不分大小写;系统或第三方改写大小写不该让链接失效
        #expect(DeepLink(url: URL(string: "PAWSTICKY://NEW")!) == .newNote)
        #expect(
            DeepLink(url: URL(string: "pawsticky://Note/1b4e28ba-2fa1-11d2-883f-0016d3cca427")!)
                == .openNote(noteID),
            "UUID 的大小写写法也都认"
        )
    }

    @Test func trailingSlashIsTolerated() {
        #expect(DeepLink(url: URL(string: "pawsticky://new/")!) == .newNote)
        #expect(
            DeepLink(url: URL(string: "pawsticky://note/1B4E28BA-2FA1-11D2-883F-0016D3CCA427/")!)
                == .openNote(noteID)
        )
    }

    @Test func queryAndFragmentAreIgnored() {
        // 为将来给链接加 ?source=small 之类的埋点留余地：它们不影响路由
        #expect(DeepLink(url: URL(string: "pawsticky://new?source=small")!) == .newNote)
        #expect(
            DeepLink(url: URL(string: "pawsticky://note/1B4E28BA-2FA1-11D2-883F-0016D3CCA427#top")!)
                == .openNote(noteID)
        )
    }

    // MARK: - 严格的部分：一律 nil

    @Test func foreignSchemesAreRejected() {
        #expect(DeepLink(url: URL(string: "https://new")!) == nil)
        #expect(DeepLink(url: URL(string: "pawit://new")!) == nil, "旧内部名不是对外 scheme")
        #expect(DeepLink(url: URL(string: "pawstickyx://new")!) == nil)
    }

    @Test func unknownHostsAreRejected() {
        #expect(DeepLink(url: URL(string: "pawsticky://")!) == nil)
        #expect(DeepLink(url: URL(string: "pawsticky://delete-all")!) == nil)
        #expect(DeepLink(url: URL(string: "pawsticky://settings")!) == nil)
    }

    @Test func noteLinksNeedExactlyOneValidUUID() {
        #expect(DeepLink(url: URL(string: "pawsticky://note")!) == nil, "缺 id")
        #expect(DeepLink(url: URL(string: "pawsticky://note/")!) == nil, "缺 id")
        #expect(DeepLink(url: URL(string: "pawsticky://note/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "pawsticky://note/12345")!) == nil)
        #expect(
            DeepLink(url: URL(string: "pawsticky://note/1B4E28BA-2FA1-11D2-883F-0016D3CCA427/edit")!) == nil,
            "多余路径段"
        )
    }

    @Test func newLinkRejectsExtraPath() {
        #expect(DeepLink(url: URL(string: "pawsticky://new/extra")!) == nil)
    }

    // MARK: - 小组件点击去哪

    @Test func widgetTapOpensTheShownNote() {
        let note = Note(id: noteID, text: "Buy milk")
        #expect(DeepLink.widgetTap(note: note) == .openNote(noteID))
    }

    @Test func widgetTapOnEmptyStateStartsANewNote() {
        // 空状态写着 "Tap to add a note"——点它就该直接进新建页，而不是只打开列表
        #expect(DeepLink.widgetTap(note: nil) == .newNote)
    }
}
