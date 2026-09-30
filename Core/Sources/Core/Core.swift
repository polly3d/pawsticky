import Foundation

/// PawIt 跨 target 共享的常量与基础模型（纯逻辑层，无 UI 依赖）。

public enum PawItInfo {
    /// 三 target（App / Widget / Watch）共享的 App Group 标识。
    public static let appGroupID = "group.com.pawit.shared"
}

/// 一条宠物便签的最小数据模型（骨架期占位，后续任务按需演进）。
public struct Note: Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String

    public init(id: UUID = UUID(), title: String, body: String = "") {
        self.id = id
        self.title = title
        self.body = body
    }
}
