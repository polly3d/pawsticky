import WatchConnectivity
import Core
import os

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

    private override init() {
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
        let session = WCSession.default
        guard session.activationState == .activated else {
            logger.debug("WCSession 未激活，跳过同步")
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.debug("未配对 Watch 或未安装 Watch App，跳过同步")
            return
        }

        guard let store = SharedStore.cachedAppGroup() else {
            logger.warning("无法访问 App Group，跳过同步")
            return
        }

        let payload = WatchPayload.fromStore(store)
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
}
