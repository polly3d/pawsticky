import Foundation
import Observation
import os

/// 手表端的「快照仓」：界面读它，传输层（WatchConnectivity）写它。
///
/// 为什么需要它（App Review 2.1(a)「手表不同步便签」）：
/// 此前界面只在启动时读一次 UserDefaults，之后经 WatchConnectivity 到达的快照虽然落了盘，
/// 却没人通知界面——手表上永远停在「Open PawSticky on iPhone」，重启 App 才出现数据。
/// 现在所有到达的快照（冷启动缓存 / context 推送 / 消息应答）一律经 `apply`，
/// 状态可观察，SwiftUI 自动重绘。
///
/// 放在 Core 而不是手表 target：手表 target 没有测试包，放这里才能脱离界面单测。
@MainActor @Observable
public final class WatchSnapshotStore {

    /// 缓存键。Watch Widget 里另有一份同值字面量——改这里必须两边同步（测试钉着这个值）。
    public static let defaultsKey = "com.pawit.watchPayload"

    private static let logger = Logger(subsystem: "com.pawit.watch", category: "snapshotStore")

    /// 当前快照。nil = 从没同步过（≠ 同步过但一条便签都没有）。
    public private(set) var payload: WatchPayload?

    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameter defaults: 手表 App 与 Watch Widget 共享的 App Group UserDefaults；
    ///   启动即从中恢复上次的快照，第一帧就有数据。
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.defaultsKey) {
            do {
                payload = try JSONDecoder().decode(WatchPayload.self, from: data)
            } catch {
                // 解码失败不静默：损坏的缓存会表现为「永远等待同步」，无诊断不可排查
                Self.logger.warning(
                    "缓存快照解码失败: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// 采纳一份到达的快照：更新可观察状态并落盘（Watch Widget 与下次启动都读这份缓存）。
    ///
    /// 来路有三条（冷启动时系统替我们存着的 context、后台推送、主动拉取的应答），
    /// 彼此可能乱序——比当前更旧的快照被拒收。同一时刻的视为幂等重复，照常采纳。
    /// - Returns: 是否采纳（调用方据此决定要不要刷新表盘）。
    @discardableResult
    public func apply(_ incoming: WatchPayload) -> Bool {
        if let current = payload, incoming.syncDate < current.syncDate { return false }
        payload = incoming
        if let data = try? JSONEncoder().encode(incoming) {
            defaults?.set(data, forKey: Self.defaultsKey)
        }
        return true
    }
}
