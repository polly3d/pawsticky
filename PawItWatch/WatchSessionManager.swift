import WatchConnectivity
import WidgetKit
import Core
import os

/// Watch 端 WatchConnectivity 管理器——接收 iPhone 推送的便签快照。
///
/// 接收到 applicationContext 后：
/// 1. 解码为 WatchPayload
/// 2. 序列化存入 App Group UserDefaults（Watch Widget 可读）
/// 3. 刷新 Widget 时间线
final class WatchSessionManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: "com.pawit.watch", category: "watchSync")

    /// App Group UserDefaults（Watch App + Watch Widget 共享）。
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: PawItInfo.appGroupID)

    /// 存储键。
    static let payloadKey = "com.pawit.watchPayload"

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

    // MARK: - 读取本地缓存

    /// 从 UserDefaults 读取最新快照（Widget 调用）。
    static func cachedPayload() -> WatchPayload? {
        guard let data = defaults?.data(forKey: payloadKey) else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession 激活失败：\(error.localizedDescription)")
            return
        }
        logger.info("WCSession 激活成功")

        // 激活后立即读取已有的 applicationContext（Watch 冷启动时可能有数据）
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            handleReceivedContext(context)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        handleReceivedContext(applicationContext)
    }

    // MARK: - Private

    private func handleReceivedContext(_ context: [String: Any]) {
        guard let payload = WatchPayload.from(context: context) else {
            logger.warning("无法解码 WatchPayload")
            return
        }

        // 序列化存入 UserDefaults（供 Widget 读取）
        if let data = try? JSONEncoder().encode(payload) {
            Self.defaults?.set(data, forKey: Self.payloadKey)
            logger.info("收到同步：\(payload.notes.count) 条便签，存入 UserDefaults")
        }

        // 刷新 Widget 时间线
        WidgetCenter.shared.reloadAllTimelines()
    }
}
