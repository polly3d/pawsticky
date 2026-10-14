import Foundation

/// App 的站内跳转目标——小组件点击（`widgetURL`）与 App 内 `onOpenURL` 共用的唯一契约。
///
/// URL 形态（scheme 与 App 的用户可见品牌一致，内部代号 PawIt 不外露）：
/// - `pawsticky://new` → 打开「新建便签」；
/// - `pawsticky://note/<UUID>` → 打开该便签的编辑页。
///
/// 解析是**严格白名单**：scheme / host / 路径形态任何一处不符都返回 nil。
/// 这个 scheme 注册进 Info.plist 之后，网页和其它 App 都能触发它，
/// 所以绝不「尽量理解」——认得的两种形态才放行，且两者都只是「打开某个页面」，
/// 不携带任何会改数据的动作。
public enum DeepLink: Equatable, Sendable {
    /// 新建便签（小组件空状态 "Tap to add a note" 的落点）。
    case newNote
    /// 打开指定便签的编辑页。
    case openNote(UUID)

    /// URL scheme。改它要同步 `project.yml` 里的 `CFBundleURLTypes`。
    public static let scheme = "pawsticky"

    /// 对应的 URL（可直接交给 `widgetURL(_:)`）。
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .newNote:
            components.host = "new"
        case .openNote(let id):
            components.host = "note"
            components.path = "/" + id.uuidString
        }
        // scheme / host 是常量、路径只含 UUID 文本，必能组出合法 URL
        return components.url!
    }

    /// 从 URL 解析；不认识的一律 nil。
    ///
    /// 有意宽容的三处：scheme / host 不分大小写（URL 规范如此）、容忍结尾斜杠、
    /// 忽略查询串与片段（将来给链接加 `?source=small` 之类埋点不会让旧版本失效）。
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              let host = components.host?.lowercased()
        else { return nil }

        // 空段（结尾斜杠 / 重复斜杠）不算路径段
        let segments = components.path.split(separator: "/").map(String.init)

        switch host {
        case "new":
            guard segments.isEmpty else { return nil }
            self = .newNote
        case "note":
            guard segments.count == 1, let id = UUID(uuidString: segments[0]) else { return nil }
            self = .openNote(id)
        default:
            return nil
        }
    }

    /// 小组件被点击时该去哪：正在展示便签就进该便签，空状态就直接新建。
    public static func widgetTap(note: Note?) -> DeepLink {
        note.map { .openNote($0.id) } ?? .newNote
    }
}
