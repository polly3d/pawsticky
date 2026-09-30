import SwiftUI
import WidgetKit
import UserNotifications
import Core

@main
struct PawItApp: App {

    @Environment(\.scenePhase) private var scenePhase
    /// Deep link 目标（通知 tap → 打开指定便签，W3-5）。
    @State private var deepLinkNoteID: UUID?

    /// 通知代理（必须在 App 初始化时设置，否则 willPresent/didReceive 不触发）。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            NoteListView()
                .bind(deepLinkNoteID: $deepLinkNoteID)
                .onReceive(NotificationCenter.default.publisher(for: .pawItDeepLink)) { notif in
                    if let noteID = notif.userInfo?["noteID"] as? UUID {
                        deepLinkNoteID = noteID
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

// MARK: - Deep link bridge

extension View {
    /// 将 deep link noteID 注入 NoteListView（绕过 SwiftUI @State 的跨视图限制）。
    func bind(deepLinkNoteID: Binding<UUID?>) -> some View {
        self.onChange(of: deepLinkNoteID.wrappedValue) { _, newValue in
            guard let newValue else { return }
            NotificationCenter.default.post(
                name: .pawItOpenNote, object: nil, userInfo: ["noteID": newValue]
            )
            deepLinkNoteID.wrappedValue = nil
        }
    }
}

extension Notification.Name {
    static let pawItDeepLink = Notification.Name("PawItDeepLink")
    static let pawItOpenNote = Notification.Name("PawItOpenNote")
}

// MARK: - AppDelegate（通知代理注册点）

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }
}

/// 通知响应代理：前台展示 + tap 后 deep link。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    /// 通知到达时 App 在前台：仍然显示 banner（默认不显示）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 用户 tap 通知：提取 noteID，通过 NotificationCenter 广播 deep link。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let noteIDString = response.notification.request.content
                .userInfo["noteID"] as? String,
              let noteID = UUID(uuidString: noteIDString) else { return }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .pawItDeepLink,
                object: nil,
                userInfo: ["noteID": noteID]
            )
        }
    }
}
