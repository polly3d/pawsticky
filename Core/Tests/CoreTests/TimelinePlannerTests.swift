import Foundation
import Testing
@testable import Core

/// Task 4 / PoC C：TimelinePlanner 纯逻辑验证（D3 刷新策略的「预计算时间线」半边）。
/// 固定 now + 注入 Calendar：跨午夜翻转在逻辑层验证——不等待真实午夜、
/// 不改模拟器时区，纯日期数学。墙钟/设备时区零参与（独立性有专测）。
/// DST 正确性由「日长 25h/23h 仍落在墙钟 00:01」直接断言。
struct TimelinePlannerTests {

    private static let ny = "America/New_York"

    // MARK: - 固定日期构造（显式时区，与设备设置无关）

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        timeZoneID: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func makePlanner(timeZoneID: String) -> TimelinePlanner {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return TimelinePlanner(calendar: calendar)
    }

    // MARK: - Step 4.1 主路径：两条目 + 唯一预算内刷新点

    @Test func middayProducesTodayAndTomorrowRolloverEntries() {
        let planner = makePlanner(timeZoneID: Self.ny)
        let now = date(2026, 9, 30, 12, 0, timeZoneID: Self.ny)  // 正午

        let slots = planner.entries(now: now)

        #expect(slots.count == 2)
        // 纯函数：同输入同输出（无隐藏状态、无墙钟）。
        #expect(slots == planner.entries(now: now))

        // 条目一「今天」：now 生效，倒计时至今晚午夜（12 小时整）。
        #expect(slots[0].date == now)
        #expect(slots[0].isDayRollover == false)
        #expect(slots[0].countdownTarget == date(2026, 10, 1, timeZoneID: Self.ny))
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 12 * 3600)

        // 条目二「明日 00:01」：跨午夜兜底，倒计时至后天午夜。
        #expect(slots[1].date == date(2026, 10, 1, 0, 1, timeZoneID: Self.ny))
        #expect(slots[1].isDayRollover == true)
        #expect(slots[1].countdownTarget == date(2026, 10, 2, timeZoneID: Self.ny))

        // 全天唯一一次预算内刷新请求 = 明日 00:01 = 最后一条目生效时刻
        // （此刻预计算内容已接管渲染，reload 只是例行续链；缺席也有 00:01 条目兜底）。
        #expect(planner.nextReloadDate(after: now) == slots[1].date)
        #expect(planner.nextReloadDate(after: now) > slots[0].date)
    }

    @Test func lastMinuteOfDayRollsOverOneMinuteAfterMidnight() {
        let planner = makePlanner(timeZoneID: Self.ny)
        let now = date(2026, 10, 1, 23, 59, timeZoneID: Self.ny)

        let slots = planner.entries(now: now)

        // 23:59 → 翻转条目在 2 分钟后（00:01），今日条目倒计时只剩 60s。
        #expect(slots[1].date == date(2026, 10, 2, 0, 1, timeZoneID: Self.ny))
        #expect(slots[1].date.timeIntervalSince(now) == 120)
        #expect(slots[0].countdownTarget == date(2026, 10, 2, timeZoneID: Self.ny))
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 60)
        // 翻转条目自己瞄准再下一个午夜。
        #expect(slots[1].countdownTarget == date(2026, 10, 3, timeZoneID: Self.ny))
    }

    // MARK: - 午夜边界

    @Test func exactMidnightCountsDownToFollowingMidnight() {
        let planner = makePlanner(timeZoneID: Self.ny)
        let now = date(2026, 10, 1, 0, 0, 0, timeZoneID: Self.ny)  // 恰在午夜

        let slots = planner.entries(now: now)

        // 恰在午夜 → 「下一个」午夜是次日午夜（倒计时满 24h），不是 now 本身。
        #expect(slots[0].countdownTarget == date(2026, 10, 2, timeZoneID: Self.ny))
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 24 * 3600)
        #expect(slots[1].date == date(2026, 10, 2, 0, 1, timeZoneID: Self.ny))
    }

    @Test func halfMinuteAfterMidnightCountsAlmostFullDay() {
        let planner = makePlanner(timeZoneID: Self.ny)
        let now = date(2026, 10, 1, 0, 0, 30, timeZoneID: Self.ny)

        let slots = planner.entries(now: now)

        #expect(slots[0].countdownTarget == date(2026, 10, 2, timeZoneID: Self.ny))
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 24 * 3600 - 30)
    }

    // MARK: - DST（America/New_York，日长 25h/23h 仍落在墙钟 00:01）

    @Test func fallBackDaySpansTwentyFiveHoursViaCalendar() {
        let planner = makePlanner(timeZoneID: Self.ny)
        // 2026-11-01 00:30 EDT：当天 02:00 EDT 回拨到 01:00 EST，是 25 小时的「今天」。
        let now = date(2026, 11, 1, 0, 30, timeZoneID: Self.ny)

        let slots = planner.entries(now: now)

        // 下一个午夜是历法上的次日 00:00（EST）：午夜到午夜整 25 小时（25h 日长的直接证明）。
        #expect(slots[0].countdownTarget == date(2026, 11, 2, timeZoneID: Self.ny))
        #expect(
            slots[0].countdownTarget.timeIntervalSince(date(2026, 11, 1, timeZoneID: Self.ny))
                == 25 * 3600
        )
        // 从 00:30 起算 = 25h − 30min。
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 25 * 3600 - 1800)
        // 翻转条目仍落在墙钟 00:01（EST）。
        #expect(slots[1].date == date(2026, 11, 2, 0, 1, timeZoneID: Self.ny))
        #expect(slots[1].date.timeIntervalSince(now) == 25 * 3600 - 1800 + 60)
        #expect(planner.nextReloadDate(after: now) == slots[1].date)
    }

    @Test func springForwardDaySpansTwentyThreeHoursViaCalendar() {
        let planner = makePlanner(timeZoneID: Self.ny)
        // 2027-03-14 00:30 EST：当天 02:00 EST 拨快到 03:00 EDT，是 23 小时的「今天」。
        let now = date(2027, 3, 14, 0, 30, timeZoneID: Self.ny)

        let slots = planner.entries(now: now)

        // 午夜到午夜整 23 小时（23h 日长的直接证明）；从 00:30 起算 = 23h − 30min。
        #expect(slots[0].countdownTarget == date(2027, 3, 15, timeZoneID: Self.ny))
        #expect(
            slots[0].countdownTarget.timeIntervalSince(date(2027, 3, 14, timeZoneID: Self.ny))
                == 23 * 3600
        )
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 23 * 3600 - 1800)
        #expect(slots[1].date == date(2027, 3, 15, 0, 1, timeZoneID: Self.ny))
        #expect(slots[1].date.timeIntervalSince(now) == 23 * 3600 - 1800 + 60)
    }

    // MARK: - 午夜跳变类时区（00:00-00:59 不存在的日子，圣地亚哥/哈瓦那/开罗/亚松森类）

    @Test func springForwardAtMidnightDayBoundsAtTrueMidnight() {
        // America/Santiago 2026-09-06：春令时跳变发生在午夜——00:00-00:59 不存在，
        // 当天从 01:00 开始。「startOfDay + 1 天」会把日界保号到次日 01:00（越界 1 小时）；
        // 正确答案永远以真实次日 00:00 为界——午夜翻转是 W4 DoD，此错误会被全家族克隆。
        let tz = "America/Santiago"
        let planner = makePlanner(timeZoneID: tz)

        // 跳变日当天：倒计时到次日 00:00（而非 01:00），翻转条目在 00:01。
        let now = date(2026, 9, 6, 12, 0, timeZoneID: tz)
        let slots = planner.entries(now: now)
        #expect(slots[0].countdownTarget == date(2026, 9, 7, timeZoneID: tz))
        #expect(slots[0].countdownTarget.timeIntervalSince(now) == 12 * 3600)
        #expect(slots[1].date == date(2026, 9, 7, 0, 1, timeZoneID: tz))
        #expect(planner.nextReloadDate(after: now) == slots[1].date)

        // 跳变日前一天：Sep 6 的真实起点是 01:00（00:00 不存在）——
        // dateInterval 端点给出的是历法事实，而非「保号午夜」。
        let eve = date(2026, 9, 5, 12, 0, timeZoneID: tz)
        #expect(planner.nextMidnight(after: eve) == date(2026, 9, 6, 1, 0, timeZoneID: tz))
        #expect(planner.nextMidnight(after: eve).timeIntervalSince(eve) == 12 * 3600)
    }

    // MARK: - 墙钟/设备时区零依赖

    @Test func plannerFollowsInjectedCalendarNotDeviceClockOrTimezone() {
        // 同一绝对时刻（UTC 2026-09-30 12:00 = 纽约 08:00 = 上海 20:00），
        // 两个注入时区给出不同的「下一个午夜」——输出只由入参决定，与设备设置无关。
        let t = date(2026, 9, 30, 12, 0, timeZoneID: "UTC")
        let nyPlanner = makePlanner(timeZoneID: Self.ny)
        let shPlanner = makePlanner(timeZoneID: "Asia/Shanghai")

        let nyMidnight = nyPlanner.nextMidnight(after: t)
        let shMidnight = shPlanner.nextMidnight(after: t)

        #expect(nyMidnight != shMidnight)
        #expect(nyMidnight == date(2026, 10, 1, timeZoneID: Self.ny))          // UTC 10-01 04:00
        #expect(shMidnight == date(2026, 10, 1, timeZoneID: "Asia/Shanghai"))  // UTC 09-30 16:00
        #expect(nyPlanner.entries(now: t) == nyPlanner.entries(now: t))
    }
}
