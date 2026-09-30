import Foundation
@testable import Core

/// W2-3 评审 Minor 的去重落点(W2-4 顺路清):测试共享 helper。
/// 此前 `makeDatabasePath` 在 SharedStoreTests/SchemaTests/ModelRoundTripTests/
/// NoteEngineTests 各有一份私有拷贝,`makeCalendar` 在 NoteEngineTests/TimelinePlannerTests
/// 重复——统一收口到此处;各套件的 `date(...)` 包装(参数形态不同)保留在本套件内,
/// 基于 `makeCalendar` 构造,不再自带时区拼装。
enum TestSupport {

    /// 全新独立数据库路径:每次调用新临时目录,保证跨运行确定性;
    /// `prefix` 隔离各测试套件(崩溃残留排查时一眼定位来源)。
    static func makeDatabasePath(prefix: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawit-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("pawit.sqlite3").path
    }

    /// 固定日历(显式时区,与设备设置无关)。
    static func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }
}
