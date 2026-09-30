import Foundation
import UserNotifications

// MARK: - 通知调度协议（W3-5）
//
// 协议封装 UNUserNotificationCenter:
// * 生产代码注入 `LiveNotificationScheduler`
// * 单测注入 `FakeNotificationScheduler`（在 CoreTests 目标内定义）
// * 编辑器保存便签后调用 `syncReminder` 一步到位（有 dueDate → 排程，无 → 取消）

/// 本地通知调度能力的协议（注入式设计,支持测试替身）。
public protocol NotificationScheduling: Sendable {
    /// 为指定便签排程一条本地通知。同 noteID 的旧通知自动被替换（identifier 唯一）。
    func schedule(noteID: UUID, at date: Date, body: String) async throws
    /// 取消指定便签的待发通知。
    func cancel(noteID: UUID) async
    /// 请求通知权限。返回 true = 用户授权。
    func requestAuthorization() async throws -> Bool
}

// MARK: - 生产实现

/// 真实调度器——包装 UNUserNotificationCenter（App 进程内使用）。
public final class LiveNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    public static let shared = LiveNotificationScheduler()

    public func schedule(noteID: UUID, at date: Date, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = "PawIt"
        content.body = body.isEmpty ? "You have a note due" : String(body.prefix(200))
        content.sound = .default
        content.userInfo = ["noteID": noteID.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: noteID.uuidString,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    public func cancel(noteID: UUID) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [noteID.uuidString])
    }

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}

// MARK: - ReminderManager（便签保存后的一步到位调度）

/// 提醒管理器:便签保存后调用 `syncReminder` 自动决定排程或取消。
/// 无状态（仅持有调度器引用），可在编辑器/仓库任一层调用。
public struct ReminderManager: Sendable {
    private let scheduler: any NotificationScheduling

    public init(scheduler: any NotificationScheduling = LiveNotificationScheduler.shared) {
        self.scheduler = scheduler
    }

    /// 同步提醒：有 dueDate 且未过期 → 排程；否则 → 取消。
    /// 调用时机：每次 note 保存后（debounce/flush/create）。
    public func syncReminder(for note: Note) async {
        if let dueDate = note.dueDate, dueDate > Date.now {
            try? await scheduler.schedule(
                noteID: note.id, at: dueDate, body: String(note.text.prefix(200))
            )
        } else {
            await scheduler.cancel(noteID: note.id)
        }
    }

    /// 便签删除时取消提醒。
    public func cancelReminder(noteID: UUID) async {
        await scheduler.cancel(noteID: noteID)
    }

    /// 首次设置到期日时请求通知权限。
    @discardableResult
    public func ensureAuthorization() async -> Bool {
        (try? await scheduler.requestAuthorization()) ?? false
    }
}
