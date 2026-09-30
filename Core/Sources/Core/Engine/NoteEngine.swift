import Foundation

// MARK: - NoteEngine(W2-3):勾选/划线/排序/日界分组/到期语义的纯逻辑层
//
// 引擎只做「值进 → 值出」的推导:输入模型值 + 注入 `Calendar` + 显式 `now`,
// 输出新值。零 Foundation 之外的依赖(不 import GRDB、不触碰 SharedStore)——
// DB-free 因此可被单测穷举,也可被 App / Widget / Watch 任意 target 复用。
//
// 职责边界:存储(SQL)归 `SharedStore`,仓库/导出归 W2-4,渲染归 W3/W4;
// 本文件是语义的**定义处**,UI 必须向这里要答案,不得自带一份副本。

/// 便签引擎命名空间(全部纯函数;状态只存在于入参)。
public enum NoteEngine {

    // MARK: 勾选语义

    /// 翻转清单项的勾选标记(Swift 值语义:返回新值,入参原值不变)。
    /// 引擎层的勾选是无条件翻转;持久化的原子读-改-写在 `SharedStore.toggleNoteItem`。
    public static func toggled(_ item: NoteItem) -> NoteItem {
        var toggled = item
        toggled.done.toggle()
        return toggled
    }

    /// 翻转便签的勾选标记(便签级开关,对应 `SharedStore.toggleFirstItem` 的引擎半边)。
    public static func toggled(_ note: Note) -> Note {
        var toggled = note
        toggled.done.toggle()
        return toggled
    }

    // MARK: 完成视觉语义

    /// 本产品完成状态的官方呈现:**经典划线**——勾选后在正文上画删除线。
    /// 这是品类领导者的 1★ 差评换来的教训:它把划线替换成 bug 不断的勾选框,
    /// 用户明确要求改回——
    /// *"[1★ v4.6.3 2025-06-07] Liked it better before the update… able to cross the
    /// things on the list instead of a ✅"*(`research/reviews-1533254320-lows.txt`)。
    /// 这是**语义标记,不是 UI 代码**:W3 编辑器 / W4 widget 渲染时必须经
    /// `strikethrough(isDone:)` 问询本样式,不得私绘勾选框。
    public static let completionStyle: CompletionStyle = .strikethrough

    /// 给定勾选状态,是否呈现完成视觉(删除线)。经典划线样式下 done ⇔ 划线;
    /// 若未来引入别的 `CompletionStyle`,此处是唯一裁决点。
    public static func strikethrough(isDone: Bool) -> Bool {
        switch completionStyle {
        case .strikethrough:
            return isDone
        }
    }

    // MARK: 排序(内存镜像;SQL 排序的权威在 SharedStore)

    /// 便签排序:(position ASC, createdAt ASC, id ASC)——与 `SharedStore.allNotes()`
    /// / `firstNote()` 同一契约(W2-3 移交项 ① 三处统一)。**store 是 SQL 排序的
    /// 权威**;引擎是同规则的内存镜像,供无 SQL 的内存场景使用(如 W2-4 导出/导入
    /// 后的重组、W4 widget 拿到数组后的稳定渲染)。id 以 `uuidString` 比较,与
    /// 库内 TEXT 列的 SQLite BINARY 序一致。
    public static func sortedNotes(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// 清单项排序:(position ASC, id ASC)——与 `SharedStore.noteItems(noteId:)` 同一契约
    /// (注意:与便签不同,清单项排序不含 createdAt;库查询即如此)。
    public static func sortedItems(_ items: [NoteItem]) -> [NoteItem] {
        items.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.id.uuidString < b.id.uuidString
        }
    }

    // MARK: 今日分组

    /// 「今日便签」:创建于今日 **或** 到期于今日的便签(保持输入相对顺序,不重排)。
    /// 分组语义(默认决策,记录在案;**作用域限定**:以下规则是 `todaysNotes` 本函数
    /// 的输出契约,UI 各入口——W3 编辑器 / W4 widget / 锁屏——是否采用本分组、
    /// 逾期条如何另列呈现,是各渲染层的取舍,不在本函数承诺内):
    /// - 创建今日即今日——今早随手记的无到期便签必须出现在今日列表;
    /// - 到期今日即今日——三天前创建、今晚到期的提醒属于今天;
    /// - **逾期不进今日**——到期早于今日起点者由 `dueStatus(.overdue)` 表达,
    ///   不再塞进今日组(今日列表保持可完成,逾期是另一件事);
    /// - `done` 不参与分组——勾选与否不影响归属(见下「午夜与 done」)。
    public static func todaysNotes(
        _ notes: [Note], now: Date, calendar: Calendar = .current
    ) -> [Note] {
        notes.filter { note in
            if DayBoundary.isSameDay(a: note.createdAt, b: now, calendar: calendar) {
                return true
            }
            if let due = note.dueDate, DayBoundary.isSameDay(a: due, b: now, calendar: calendar) {
                return true
            }
            return false
        }
    }

    // MARK: 到期语义

    /// 便签到期的四态。`today` 优先于 `overdue`:到期时刻落在今天(哪怕已过点)
    /// 就是 today;**overdue 当且仅当 dueDate 严格早于今日起点**——
    /// 「今天该做但还没做」与「已经错过」是两件事,当天不降级为逾期。
    public static func dueStatus(
        _ note: Note, now: Date, calendar: Calendar = .current
    ) -> DueStatus {
        guard let due = note.dueDate else { return .none }
        if DayBoundary.isSameDay(a: due, b: now, calendar: calendar) { return .today }
        if due < DayBoundary.startOfToday(now: now, calendar: calendar) { return .overdue }
        return .upcoming
    }

    /// 是否逾期:即 `dueStatus == .overdue`(单一定义在 `dueStatus`,勿另立标准)。
    /// nil 到期永不逾期;日界取 `DayBoundary.startOfToday`(TimelinePlanner 端点真相,
    /// 午夜跳变日为 01:00 类),不做固定 86400 秒假设。
    public static func isOverdue(
        _ note: Note, now: Date, calendar: Calendar = .current
    ) -> Bool {
        dueStatus(note, now: now, calendar: calendar) == .overdue
    }

    // MARK: 午夜与 done(W2 登记项③的决策记录)

    /// **决策(2026-09-30,W2 评审登记项③;w3.v1 设计时复核):`done` 跨午夜持久保留。**
    /// 跨午夜翻转**不**自动重置勾选,也**不**新增 `doneAt` 列;午夜只影响
    /// 「今日」分组(本引擎 `todaysNotes`)与 W7 喂养结算。
    /// 理由——最少意外原则:便签不是打卡器,用户昨晚勾掉的事不该半夜被系统偷偷
    /// 「翻开」;隔夜待办的真实状态(还挂着的逾期事项)由到期语义
    /// (`dueStatus`/`isOverdue`)与今日分组表达,而不是篡改数据本身。
    /// 本引擎的一切日界函数都只读 `done`、从不写——唯一能改 `done` 的入口是
    /// 显式勾选 `toggled(_:)`(以及 store 侧的两个 toggle 事务)。
}

/// 完成状态的呈现样式(语义标记,非 UI;见 `NoteEngine.completionStyle`)。
public enum CompletionStyle: Equatable, Sendable {
    /// 经典划线:勾选后正文加删除线(产品唯一官方完成视觉)。
    case strikethrough
}

/// 到期四态(见 `NoteEngine.dueStatus`)。
public enum DueStatus: Equatable, Sendable {
    /// 未设到期。
    case none
    /// 到期日在今天(当天即使已过点仍是 today,不降级为 overdue)。
    case today
    /// 到期日在未来。
    case upcoming
    /// 到期时刻严格早于今日起点(已经错过)。
    case overdue
}

// MARK: - 日界(DayBoundary):TimelinePlanner 日界的委托门面
//
// 「一天」的定义只有一处真源:`TimelinePlanner` 的本地日区间
// (`dateInterval(of:.day)` 端点;午夜跳变日的起点是 01:00 类真实首时刻)。
// 本命名空间**只做委托,不做任何日算术**——防两处午夜数学漂移
// (W1 备忘录 W4 顺手项的落地)。

/// 便签引擎的日界问询入口(全部委托 `TimelinePlanner`,单一事实源)。
public enum DayBoundary {

    /// 两个时刻是否同属注入日历下的同一「本地日」。
    public static func isSameDay(
        a: Date, b: Date, calendar: Calendar = .current
    ) -> Bool {
        TimelinePlanner(calendar: calendar).isSameDay(a, b)
    }

    /// 今日起点(注入日历下的本地日区间 start 端点)。
    /// `NoteEngine.isOverdue` 的「今天之前」分界即取此处。
    public static func startOfToday(
        now: Date, calendar: Calendar = .current
    ) -> Date {
        TimelinePlanner(calendar: calendar).startOfDay(for: now)
    }
}
