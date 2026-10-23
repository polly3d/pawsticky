import WatchConnectivity
import WidgetKit
import Core
import os

/// Watch 端 WatchConnectivity 管理器——接收 iPhone 推送的便签快照，并在需要时主动向 iPhone 要。
///
/// 快照有三条来路，全部汇入 `store`（界面读它，Watch Widget 读它落的盘）：
/// 1. 激活后系统替我们存着的最新 applicationContext（冷启动时可能已有数据）；
/// 2. iPhone 在便签变更 / 回前台 / 手表 App 装好时推来的 applicationContext；
/// 3. 我们主动问 iPhone 要、由它应答（激活后、回前台、连通性恢复时）。
///
/// 第 3 条是兜底：推送只在 iPhone 自己这边有事发生时才触发，手表 App 晚于便签装好、
/// 或错过一次推送时没人会补推——那就是 App Review 2.1(a) 的现场。
///
/// `@MainActor`：`store` 是界面状态，只能在主线程改；WCSession 的回调在它自己的串行队列上，
/// 所以下面的代理方法都是 `nonisolated`，解码完再用 `Task { @MainActor in … }` 切回来。
@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    /// 界面与缓存的唯一来源（App Group UserDefaults，Watch Widget 同读这份落盘）。
    let store = WatchSnapshotStore(defaults: UserDefaults(suiteName: PawItInfo.appGroupID))

    private nonisolated let logger = Logger(subsystem: "com.pawit.watch", category: "watchSync")

    private override init() {
        super.init()
    }

    // MARK: - 激活

    /// Watch App 启动时调用。
    func activate() {
        guard WCSession.isSupported() else {
            logger.info("WCSession 不支持")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - 主动要快照

    /// 向 iPhone 要一份最新快照；iPhone 端没在运行时系统会替这条消息把它在后台拉起来。
    /// 还不能要（未激活 / iPhone 暂不可达）就直接返回——连通性恢复时 `sessionReachabilityDidChange` 会再要一次。
    func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            logger.debug("暂不能向 iPhone 要快照（未激活或不可达）")
            return
        }
        // 显式 @Sendable：这两个闭包由 WCSession 在非主线程调用，不能被推断成 @MainActor
        session.sendMessage(
            WatchPayload.snapshotRequest,
            replyHandler: { @Sendable [weak self] reply in
                // 空应答 = iPhone 此刻给不出快照（读不到库等）：当没收到，保留缓存里的好数据
                guard let payload = WatchPayload.from(context: reply) else { return }
                Task { @MainActor in self?.apply(payload, from: "主动拉取的应答") }
            },
            errorHandler: { @Sendable [logger = self.logger] error in
                logger.warning("向 iPhone 要快照失败：\(error.localizedDescription)")
            }
        )
    }

    // MARK: - 采纳快照

    private func apply(_ payload: WatchPayload, from source: String) {
        // 比当前更旧的快照被拒收（几条来路可能乱序）：什么都不做
        guard store.apply(payload) else { return }
        logger.info("收到同步（\(source, privacy: .public)）：\(payload.notes.count) 条便签")
        // 刷新 Widget 时间线（Widget 读的是 store 刚落盘的缓存）
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - WCSessionDelegate（回调在 WCSession 的非主串行队列上）

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession 激活失败：\(error.localizedDescription)")
            return
        }
        logger.info("WCSession 激活成功")

        // 先取系统替我们存着的最新 context（冷启动时可能已有数据），再主动要一份新的
        let cached = WatchPayload.from(context: session.receivedApplicationContext)
        Task { @MainActor in
            if let cached { self.apply(cached, from: "激活时已有的 context") }
            self.requestSnapshot()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let payload = WatchPayload.from(context: applicationContext) else {
            logger.warning("无法解码 WatchPayload")
            return
        }
        Task { @MainActor in self.apply(payload, from: "iPhone 推送") }
    }

    /// iPhone 变得可达（例如激活时还没连上、随后连上了）：之前那次「要」被跳过了，现在补要。
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestSnapshot() }
    }
}
