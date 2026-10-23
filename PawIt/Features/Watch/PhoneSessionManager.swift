import WatchConnectivity
import Core
import os

/// `WCSession` 里 `PhoneSessionManager` 真正用到的那一小片——给测试替身留的缝。
/// 生产环境就是 `WCSession.default` 本身（下面的空 extension 让它直接符合）。
protocol WatchSessionProviding: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

extension WCSession: WatchSessionProviding {}

/// iPhone 端 WatchConnectivity 管理器——把便签快照推送到 Apple Watch。
///
/// 使用 `updateApplicationContext`（最新状态语义，非队列），Watch 端
/// 收到后存入本地 UserDefaults 供 Widget 读取。
///
/// 触发时机：
/// - App 启动时激活 session
/// - 便签变更后调 `syncToWatch()`
/// - 宠物切换后调 `syncToWatch()`
final class PhoneSessionManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = PhoneSessionManager()

    private let logger = Logger(subsystem: "com.pawit.app", category: "watchSync")

    /// 与手表之间的那条会话（生产环境是 `WCSession.default`，测试注入替身）。
    private let session: any WatchSessionProviding

    /// 构建当前全量快照；nil = App Group 不可用。
    private let makePayload: @Sendable () -> WatchPayload?

    private override convenience init() {
        self.init(session: WCSession.default) {
            SharedStore.cachedAppGroup().map(WatchPayload.fromStore)
        }
    }

    /// internal：测试注入假会话与固定快照。
    init(session: any WatchSessionProviding, makePayload: @escaping @Sendable () -> WatchPayload?) {
        self.session = session
        self.makePayload = makePayload
        super.init()
    }

    // MARK: - 激活

    /// App 启动时调用，激活 WCSession。
    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WCSession 不支持（无配对 Watch 或非 iPhone）")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - 同步

    /// 将当前全量便签快照推送到 Watch。
    /// 调用点：NoteListView.reloadNotes() 后、PetSelectionView 选宠后。
    func syncToWatch() {
        guard session.activationState == .activated else {
            logger.debug("WCSession 未激活，跳过同步")
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.debug("未配对 Watch 或未安装 Watch App，跳过同步")
            return
        }

        guard let payload = makePayload() else {
            logger.warning("无法访问 App Group，跳过同步")
            return
        }

        do {
            try session.updateApplicationContext(payload.toDictionary())
            logger.info("同步到 Watch 成功：\(payload.notes.count) 条便签")
        } catch {
            logger.error("同步到 Watch 失败：\(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession 激活失败：\(error.localizedDescription)")
        } else {
            logger.info("WCSession 激活成功：\(activationState.rawValue)")
            syncToWatch()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        logger.debug("WCSession inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        logger.debug("WCSession deactivated，重新激活")
        session.activate()
    }

    /// 手表 App 装好 / 卸载、配对变化时系统会调这个回调。
    ///
    /// 之前没实现它：便签先于手表 App 存在时，`syncToWatch()` 因「未安装」被跳过，
    /// 手表 App 随后装好了却没人通知 iPhone，也就没人补推——手表上永远是空的
    /// （App Review 2.1(a)：审核备注让审核员「先建便签、再从 Watch App 里装手表端」，正好踩中）。
    /// 状态判断仍在 `syncToWatch()` 的守卫里：此刻仍没有可推送的手表 App 就会照常跳过。
    func sessionWatchStateDidChange(_ session: WCSession) {
        logger.info("Watch 状态变化，重新同步")
        syncToWatch()
    }

    /// 手表主动要快照（它缓存为空 / 回前台 / 连通性恢复时）。
    /// iPhone 端没在运行时，系统会为这条消息把它在后台拉起来——所以手表可以放心地「想要就要」。
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler(snapshotReply(to: message))
    }

    /// 应答内容。认不得的消息和读不到库的情况都回空字典——
    /// 手表端解码不出快照就当没收到，不会拿一份空快照盖掉它缓存里的好数据。
    /// internal：测试直接驱动，不必构造 WCSession 回调。
    func snapshotReply(to message: [String: Any]) -> [String: Any] {
        guard WatchPayload.isSnapshotRequest(message), let payload = makePayload() else { return [:] }
        return payload.toDictionary()
    }
}
