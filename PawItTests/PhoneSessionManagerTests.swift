import Testing
import Foundation
import WatchConnectivity
import Core
@testable import PawIt

/// 假的手表会话：记录 iPhone 往手表推了什么，状态由用例随意拨。
private final class FakeWatchSession: WatchSessionProviding, @unchecked Sendable {
    var activationState: WCSessionActivationState = .activated
    var isPaired = true
    var isWatchAppInstalled = true
    private(set) var sentContexts: [[String: Any]] = []

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        sentContexts.append(applicationContext)
    }
}

/// iPhone → 手表同步的时序钉子——App Review 2.1(a)「手表不同步便签」的回归测试。
///
/// 审核员的路径：先在 iPhone 上建便签 → 再按审核备注「从 iPhone 的 Watch App 里安装手表端」。
/// 当时 iPhone 只在「激活 / 回前台 / 便签变更」时才推送，手表 App 装好这件事没人通知它，
/// 于是手表上永远是空的（现场日志：装好手表端之后 iPhone 一行日志都没有）。
struct PhoneSessionManagerTests {

    private let payload = WatchPayload(
        notes: [.init(id: "N1", text: "Test", done: true, dueDate: nil, style: nil, items: [])],
        selectedPet: .init(species: "cat", displayName: "Tabby"),
        syncDate: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )

    private func makeManager(
        _ session: FakeWatchSession, payload: WatchPayload?
    ) -> PhoneSessionManager {
        PhoneSessionManager(session: session, makePayload: { payload })
    }

    // MARK: - 审核员的路径：手表 App 晚于便签装好

    @Test func watchAppInstalledAfterNotesExistGetsASnapshotWithoutAnyUserAction() {
        let session = FakeWatchSession()
        session.isWatchAppInstalled = false
        let manager = makeManager(session, payload: payload)

        // ① 便签已存在，手表 App 还没装：这次同步被跳过（这一步本来就该跳过）
        manager.syncToWatch()
        #expect(session.sentContexts.isEmpty)

        // ② 用户随后在 iPhone 的 Watch App 里把手表端装好——系统通知 iPhone「手表状态变了」
        session.isWatchAppInstalled = true
        manager.sessionWatchStateDidChange(WCSession.default)

        // ③ iPhone 必须自己把之前被跳过的快照补推过去，不能等用户碰巧回前台 / 改便签
        #expect(session.sentContexts.count == 1, "手表 App 装好后应补推一次")
        #expect(session.sentContexts.first.flatMap(WatchPayload.from(context:)) == payload)
    }

    @Test func watchStateChangeWhileStillNotInstalledSendsNothing() {
        // 例如只是解除配对 / 切换手表：没有可推送的对象时不该硬推
        let session = FakeWatchSession()
        session.isWatchAppInstalled = false
        let manager = makeManager(session, payload: payload)

        manager.sessionWatchStateDidChange(WCSession.default)

        #expect(session.sentContexts.isEmpty)
    }

    // MARK: - 既有守卫不能被接缝改动带歪

    @Test func nothingIsSentBeforeTheSessionIsActivated() {
        let session = FakeWatchSession()
        session.activationState = .notActivated
        let manager = makeManager(session, payload: payload)

        manager.syncToWatch()

        #expect(session.sentContexts.isEmpty)
    }

    @Test func nothingIsSentWhenAppGroupIsUnavailable() {
        let session = FakeWatchSession()
        let manager = makeManager(session, payload: nil)

        manager.syncToWatch()

        #expect(session.sentContexts.isEmpty, "读不到库时宁可不推，也不要把空快照推过去盖掉手表上的好数据")
    }

    // MARK: - 手表主动要快照

    @Test func snapshotRequestIsAnsweredWithTheCurrentPayload() {
        let manager = makeManager(FakeWatchSession(), payload: payload)

        let reply = manager.snapshotReply(to: WatchPayload.snapshotRequest)

        #expect(WatchPayload.from(context: reply) == payload)
        // WCSession 的应答字典同样只接受属性列表类型
        #expect(PropertyListSerialization.propertyList(reply, isValidFor: .binary))
    }

    @Test func messagesThatAreNotSnapshotRequestsGetAnEmptyReply() {
        let manager = makeManager(FakeWatchSession(), payload: payload)

        #expect(manager.snapshotReply(to: [:]).isEmpty)
        #expect(manager.snapshotReply(to: ["request": "delete-everything"]).isEmpty)
    }

    @Test func snapshotRequestGetsAnEmptyReplyWhenAppGroupIsUnavailable() {
        let manager = makeManager(FakeWatchSession(), payload: nil)

        #expect(manager.snapshotReply(to: WatchPayload.snapshotRequest).isEmpty)
    }
}
