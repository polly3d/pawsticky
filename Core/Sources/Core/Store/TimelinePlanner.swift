import Foundation

// MARK: - 《刷新策略表》（Task 4 / PoC C —— W1 备忘录素材）
//
// 决策 D3：**内容变更永远由「用户动作」驱动（intent/前台），绝不为展示效果依赖系统刷新。**
// 背景：Widget 每日刷新预算约 40-70 次，且系统从不保证按时执行——品类领导者的第一大
// 差评类就是「widget 永远不更新」（`research/reviews-1533254320-lows.txt` 痛点 1）。
// 因此 PawIt 的每一条内容更新路径都有唯一明确的驱动者；下表没有任何一行依赖
// 「系统按日程自动刷新 widget」：
//
// | 场景              | 谁驱动更新             | 机制                                                                              | 消耗刷新预算？                          |
// |-------------------|------------------------|-----------------------------------------------------------------------------------|-----------------------------------------|
// | App 内编辑内容     | 用户前台动作            | 落盘后 `WidgetCenter.reloadTimelines`（W5 接入；scenePhase 离开前台时触发）             | 是——由用户动作主动花费，不是祈祷系统     |
// | Widget 内勾选事项  | intent perform()       | `ToggleItemIntent` 原子写共享库，系统对交互式 widget 内建自动重绘（不拉起主 App）        | 否——交互重绘不走每日预算                |
// | 跨午夜翻转         | 预计算时间线（本类型）  | entries 预生成「今天 + 明日 00:01」两条；即使预算 reload 缺席，00:01 条目也正确渲染新的一天 | 是——每天至多 1 次（policy `.after`），且内容连续性不依赖它 |
// | 倒计时显示         | `Text(timerInterval:)` 自更新 | 系统按秒自绘文字，不 wake 扩展、不发起 reload                                      | 否——零预算（PoC C 的核心发现）           |
// | 提醒到期           | 本地通知                | `UNUserNotificationCenter` 预调度（W3）；通知到达不刷新 widget，用户点开走前台路径      | 否——通知与刷新预算无关                  |
//
// 结论：五类场景分别由 intent / 前台 reload / 预计算条目 / 零预算自绘文字 / 本地通知驱动；
// 刷新预算每天至多花 1 次（午夜续链），且这一次也被「明日 00:01」条目兜底——
// 「不刷新」差评的技术根因被结构性排除。

/// 单条预计算时间线条目（Core 侧纯值类型；widget target 负责映射为 `WidgetKit.Timeline.Entry`）。
public struct TimelineSlot: Equatable, Sendable {
    /// 条目开始生效的时刻。
    public let date: Date
    /// 倒计时目标：本条目所覆盖「本地日」的下一个午夜（00:00）。
    public let countdownTarget: Date
    /// 是否为跨午夜翻转条目（明日 00:01 生效的「新的一天」兜底条目）。
    public let isDayRollover: Bool

    public init(date: Date, countdownTarget: Date, isDayRollover: Bool) {
        self.date = date
        self.countdownTarget = countdownTarget
        self.isDayRollover = isDayRollover
    }
}

/// 刷新策略的纯逻辑层：给定 `now`，预计算时间线条目与全天唯一一次预算内刷新时刻。
///
/// - 纯函数：一切由入参 `now` + 注入的 `Calendar` 推导，内部不读墙钟（测试注入固定日期即可）。
/// - DST 正确：日算术全部经 `Calendar`——既有 25h/23h 的日长变化（纽约 2026-11-01 /
///   2027-03-14），也有「午夜无 00:00」的跳变日（圣地亚哥 2026-09-06 类，日界取
///   `dateInterval(of:.day)` 端点而非 startOfDay 保号值）；不做固定 86400 秒假设。
/// - 已知限制（Known limitation）：条目按 init 时捕获的时区预计算。若用户在 widget
///   已加载后更改设备时区，倒计时仍指向旧时区的午夜，直到下一次 00:01 预算 reload
///   才换算到新时区（最长 ≤24 小时，之后自愈）。App 前台若感知到时区变化，可主动
///   `WidgetCenter.reloadTimelines` 提前自愈（W5 接入）。
public struct TimelinePlanner: Sendable {
    private let calendar: Calendar

    /// - Parameter calendar: 默认 `Calendar.current`；测试注入固定时区的日历。
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 预计算两个条目（`Timeline(policy:.after(nextReloadDate))` 的内容来源）：
    /// 1. 今天：`now` 生效，倒计时至今晚午夜；
    /// 2. 明日 00:01：跨午夜兜底条目，倒计时至后天午夜——预算 reload 缺席时仍渲染正确的新一天状态。
    public func entries(now: Date) -> [TimelineSlot] {
        let rolloverDate = nextRolloverDate(after: now)
        return [
            TimelineSlot(date: now, countdownTarget: nextMidnight(after: now), isDayRollover: false),
            TimelineSlot(
                date: rolloverDate,
                countdownTarget: nextMidnight(after: rolloverDate),
                isDayRollover: true
            ),
        ]
    }

    /// 全天唯一一次预算内刷新请求时刻：明日 00:01（本地），即翻转条目的生效时刻。
    /// 此刻预计算内容已接管渲染，系统再来取新时间线只是例行续链；reload 延迟或缺席
    /// 都不影响内容正确性（这正是「不为展示效果依赖系统刷新」）。
    public func nextReloadDate(after now: Date) -> Date {
        nextRolloverDate(after: now)
    }

    /// 下一个本地午夜（00:00）。`now` 恰为午夜时返回次日午夜（倒计时满 24 小时）。
    /// 午夜跳变类时区（圣地亚哥/哈瓦那/开罗/亚松森类）返回真实次日 00:00
    /// （跳变日当天即 01:00）。
    public func nextMidnight(after now: Date) -> Date {
        startOfNextDay(after: now)
    }

    /// 「同一天」判定（W2-3 NoteEngine 消费）：两个时刻落在同一本地日区间。
    /// 与 `nextMidnight`/`entries` 同一日界真相（下方 `dayInterval` 单点派生），
    /// DST 跳变日（午夜无 00:00 的日子，起点 01:00）也保持一致。
    public func isSameDay(_ a: Date, _ b: Date) -> Bool {
        dayInterval(for: a) == dayInterval(for: b)
    }

    /// 本地日起点（日界区间的 start 端点）。常态日即 00:00；午夜跳变日是真实
    /// 首时刻（如圣地亚哥 2026-09-06 的 01:00）——历法事实，而非保号午夜。
    /// NoteEngine 的到期语义（overdue 分界）经由 `DayBoundary.startOfToday` 消费此处。
    public func startOfDay(for date: Date) -> Date {
        dayInterval(for: date).start
    }

    // MARK: - 私有日算术（全部经 Calendar，DST 安全）

    /// 明日 00:01（本地）：跨午夜兜底条目生效时刻 = 唯一预算内刷新请求时刻。
    private func nextRolloverDate(after now: Date) -> Date {
        date(byAdding: .minute, value: 1, to: startOfNextDay(after: now))
    }

    private func startOfNextDay(after date: Date) -> Date {
        // 次日边界 = 当前「本地日」区间的 end（历法真相，跳变日也不例外）。
        // 不能用 startOfDay + 1 天：在午夜无 00:00 的日子（圣地亚哥/哈瓦那/开罗/
        // 亚松森类时区，春令时跳变发生在 00:00），startOfDay 返回 01:00，
        // 加一天把「当日 01:00」保号成「次日 01:00」，越过真实日界 1 小时。
        // dateInterval 的 end 在此类日子给出真实次日 00:00；25h/23h 日（纽约
        // 双向往证）与常态日结果不变。
        dayInterval(for: date).end
    }

    /// 本地日区间——全部「日」算术的唯一取值点（单一事实源，W1 备忘录 W4 顺手项：
    /// NoteEngine 的午夜语义必须消费此处定义，防两处漂移）。
    private func dayInterval(for date: Date) -> DateInterval {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            fatalError("TimelinePlanner: 日历算术对可表示日期不可能返回 nil（本地日区间）")
        }
        return interval
    }

    /// Calendar 算术仅对「不可表示的日期」返回 nil（系统时钟不可能给出）；
    /// 防御性 trap 而非静默错值。
    private func date(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date {
        guard let advanced = calendar.date(byAdding: component, value: value, to: date) else {
            fatalError("TimelinePlanner: 日历算术对可表示日期不可能返回 nil（\(component) +\(value)）")
        }
        return advanced
    }
}
