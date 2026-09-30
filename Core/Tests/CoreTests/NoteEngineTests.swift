import Foundation
import Testing
import GRDB
@testable import Core

/// W2-3:NoteEngine 纯逻辑验证。引擎零 Foundation 之外的依赖(不 import GRDB),
/// 一切由入参(模型值 + 注入 Calendar + now)推导——DB-free,测试注入固定日期即可。
/// 日界一律消费 TimelinePlanner 的定义(单一事实源,见 DayBoundary 委托链)。
struct NoteEngineTests {

    // MARK: - 固定日期构造(显式时区,与设备设置无关;仿 TimelinePlannerTests)

    private func makeCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        timeZoneID: String
    ) -> Date {
        var calendar = makeCalendar(timeZoneID: timeZoneID)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func fixed(_ epoch: TimeInterval) -> Date {
        Date(timeIntervalSince1970: epoch)
    }

    private static let ny = "America/New_York"
    private static let shanghai = "Asia/Shanghai"

    /// 全新独立数据库路径(引擎↔store 同序契约用例;每次调用新临时目录保证确定性)。
    private func makeDatabasePath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pawit-w23-engine-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("pawit.sqlite3").path
    }

    // MARK: - 勾选语义:值语义的 toggled(_:) + 经典划线

    @Test func toggledItemFlipsDoneAndPreservesEverythingElse() {
        let original = NoteItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            noteId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "铲屎", done: false, position: 3, createdAt: fixed(1)
        )

        let flipped = NoteEngine.toggled(original)

        #expect(flipped.done == true)
        #expect(flipped.id == original.id)
        #expect(flipped.noteId == original.noteId)
        #expect(flipped.text == original.text)
        #expect(flipped.position == original.position)
        #expect(flipped.createdAt == original.createdAt)
        // Swift 值语义:入参原值不变;二次翻转回到初值(幂等往返)。
        #expect(original.done == false)
        #expect(NoteEngine.toggled(flipped) == original)
    }

    @Test func toggledNoteFlipsDoneAndPreservesEverythingElse() {
        let original = Note(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            text: "喂食", createdAt: fixed(1), done: false,
            dueDate: fixed(1_800_000_000), position: 5
        )

        let flipped = NoteEngine.toggled(original)

        #expect(flipped.done == true)
        #expect(flipped.id == original.id)
        #expect(flipped.text == original.text)
        #expect(flipped.createdAt == original.createdAt)
        #expect(flipped.dueDate == original.dueDate)
        #expect(flipped.position == original.position)
        #expect(original.done == false)
        #expect(NoteEngine.toggled(flipped) == original)
    }

    /// 完成视觉语义钉子:经典划线是本产品唯一的完成呈现(品类领导者的 1★ 差评——
    /// v4.6.3 用 bug 不断的 ✅ 替换划线:research/reviews-1533254320-lows.txt)。
    /// 引擎只给语义标记,不做 UI;UI(W3/W4)必须向这里要答案。
    @Test func completionStyleIsClassicStrikethrough() {
        #expect(NoteEngine.completionStyle == .strikethrough)
        #expect(NoteEngine.strikethrough(isDone: true) == true)
        #expect(NoteEngine.strikethrough(isDone: false) == false)
    }

    // MARK: - 排序:引擎镜像 store 的 SQL 排序(store 是权威,见 SharedStore.allNotes)

    @Test func sortedNotesOrdersByPositionThenCreatedAtThenID() {
        let sameInstant = fixed(1_000_000)
        let idSmall = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idLarge = UUID(uuidString: "FFFF0000-0000-0000-0000-000000000002")!
        let noteC = Note(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, text: "C pos2", createdAt: sameInstant, position: 2)
        let noteA = Note(id: idLarge, text: "A pos0 id大", createdAt: sameInstant, position: 0)
        let noteD = Note(id: idSmall, text: "D pos0 id小", createdAt: sameInstant, position: 0)
        let noteB = Note(id: UUID(), text: "B pos1", createdAt: fixed(2_000_000), position: 1)

        // 乱序输入(与 ModelRoundTripTests 的落库用例同一 fixture):顺序只来自排序键。
        #expect(NoteEngine.sortedNotes([noteC, noteA, noteD, noteB]) == [noteD, noteA, noteB, noteC])
        // 空表与单元素平凡情形。
        #expect(NoteEngine.sortedNotes([]) == [])
        #expect(NoteEngine.sortedNotes([noteB]) == [noteB])
    }

    @Test func sortedItemsOrdersByPositionThenID() {
        let idSmall = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let idLarge = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let pos0Large = NoteItem(id: idLarge, noteId: UUID(), text: "pos0 id大", position: 0, createdAt: fixed(1))
        let pos0Small = NoteItem(id: idSmall, noteId: UUID(), text: "pos0 id小", position: 0, createdAt: fixed(2))
        let pos1 = NoteItem(id: UUID(), noteId: UUID(), text: "pos1", position: 1, createdAt: fixed(3))
        let pos2 = NoteItem(id: UUID(), noteId: UUID(), text: "pos2", position: 2, createdAt: fixed(4))

        // 清单项排序无 createdAt 键(store 的 noteItems 查询即 position → id)。
        #expect(NoteEngine.sortedItems([pos2, pos0Large, pos1, pos0Small]) == [pos0Small, pos0Large, pos1, pos2])
        #expect(NoteEngine.sortedItems([]) == [])
    }

    /// 引擎与 store 同序契约:DB 里乱序落库,store 的 SQL 读取序(权威)必须等于
    /// 引擎对同批内存值的排序——导出/导入(W2-4)等无 SQL 场景的兜底依据。
    @Test func engineSortingAgreesWithStoreQueries() async throws {
        let path = makeDatabasePath()
        let store = try SharedStore(databasePath: path)
        let noteID = UUID()

        let sameInstant = fixed(1_000_000)
        let notes = [
            Note(id: UUID(), text: "pos2", createdAt: sameInstant, position: 2),
            Note(id: noteID, text: "pos0", createdAt: sameInstant, position: 0),
            Note(id: UUID(), text: "pos1", createdAt: fixed(2_000_000), position: 1),
        ]
        let items = [
            NoteItem(id: UUID(), noteId: noteID, text: "pos2", position: 2, createdAt: fixed(1)),
            NoteItem(id: UUID(), noteId: noteID, text: "pos0", position: 0, createdAt: fixed(2)),
            NoteItem(id: UUID(), noteId: noteID, text: "pos1", position: 1, createdAt: fixed(3)),
        ]
        for note in notes { try await store.upsertNote(note) }
        for item in items { try await store.addNoteItem(item) }

        let fresh = try SharedStore(databasePath: path)
        #expect(try fresh.allNotes() == NoteEngine.sortedNotes(notes))
        #expect(try fresh.noteItems(noteId: noteID) == NoteEngine.sortedItems(items))
    }

    // MARK: - 日界:委托 TimelinePlanner 单一事实源(登记项③的落点之一)

    @Test func isSameDayFollowsInjectedCalendarDayBoundary() {
        let cal = makeCalendar(timeZoneID: Self.shanghai)
        let noon = date(2026, 9, 30, 12, timeZoneID: Self.shanghai)

        #expect(DayBoundary.isSameDay(a: noon, b: noon, calendar: cal))
        #expect(DayBoundary.isSameDay(
            a: date(2026, 9, 30, 0, 0, timeZoneID: Self.shanghai),
            b: date(2026, 9, 30, 23, 59, timeZoneID: Self.shanghai),
            calendar: cal
        ))
        #expect(!DayBoundary.isSameDay(
            a: date(2026, 9, 30, 23, 59, timeZoneID: Self.shanghai),
            b: date(2026, 10, 1, 0, 0, timeZoneID: Self.shanghai),
            calendar: cal
        ))

        // 同一绝对时刻,注入时区决定「是哪天」:UTC 10-01 02:00 = 上海 10-01 10:00 = 纽约 09-30 22:00。
        let t = date(2026, 10, 1, 2, 0, timeZoneID: "UTC")
        #expect(DayBoundary.isSameDay(
            a: t,
            b: date(2026, 10, 1, 0, 0, timeZoneID: Self.shanghai),
            calendar: makeCalendar(timeZoneID: Self.shanghai)
        ))
        #expect(!DayBoundary.isSameDay(
            a: t,
            b: date(2026, 10, 1, 0, 0, timeZoneID: Self.ny),
            calendar: makeCalendar(timeZoneID: Self.ny)
        ))
        #expect(DayBoundary.isSameDay(
            a: t,
            b: date(2026, 9, 30, 12, 0, timeZoneID: Self.ny),
            calendar: makeCalendar(timeZoneID: Self.ny)
        ))
    }

    @Test func isSameDayIsDSTCorrectOnLongDaysAndMidnightJumpDays() {
        let ny = makeCalendar(timeZoneID: Self.ny)
        // 25h 日(纽约 2026-11-01 回拨):00:30 EDT 与 23:30 EST 同一日;与次日 00:30 不同日。
        #expect(DayBoundary.isSameDay(
            a: date(2026, 11, 1, 0, 30, timeZoneID: Self.ny),
            b: date(2026, 11, 1, 23, 30, timeZoneID: Self.ny),
            calendar: ny
        ))
        #expect(!DayBoundary.isSameDay(
            a: date(2026, 11, 1, 23, 30, timeZoneID: Self.ny),
            b: date(2026, 11, 2, 0, 30, timeZoneID: Self.ny),
            calendar: ny
        ))

        // 午夜跳变日(圣地亚哥 2026-09-06,00:00-00:59 不存在):真实首时刻 01:00 与当日 12:00
        // 同日;前一日最后一刻与 01:00 不同日——判定与 TimelinePlanner 的日界端点同源。
        let santiago = makeCalendar(timeZoneID: "America/Santiago")
        #expect(DayBoundary.isSameDay(
            a: date(2026, 9, 6, 1, 0, timeZoneID: "America/Santiago"),
            b: date(2026, 9, 6, 12, 0, timeZoneID: "America/Santiago"),
            calendar: santiago
        ))
        #expect(!DayBoundary.isSameDay(
            a: date(2026, 9, 5, 23, 59, timeZoneID: "America/Santiago"),
            b: date(2026, 9, 6, 1, 0, timeZoneID: "America/Santiago"),
            calendar: santiago
        ))
    }

    /// 「今日起点」与 TimelinePlanner 的日界端点同源:跳变日的起点是真实首时刻 01:00,
    /// 不是保号的 00:00——isOverdue 以此为「今天之前」的分界,不得自备午夜数学。
    @Test func startOfTodayMatchesTimelinePlannerDayBoundary() {
        let ny = makeCalendar(timeZoneID: Self.ny)
        #expect(DayBoundary.startOfToday(
            now: date(2026, 10, 1, 12, timeZoneID: Self.ny),
            calendar: ny
        ) == date(2026, 10, 1, timeZoneID: Self.ny))

        let santiago = makeCalendar(timeZoneID: "America/Santiago")
        #expect(DayBoundary.startOfToday(
            now: date(2026, 9, 6, 12, timeZoneID: "America/Santiago"),
            calendar: santiago
        ) == date(2026, 9, 6, 1, 0, timeZoneID: "America/Santiago"))
    }

    // MARK: - 今日分组(创建今日 OR 到期今日;逾期不进今日;done 不参与分组)

    @Test func todaysNotesGroupsCreatedTodayOrDueToday() {
        let cal = makeCalendar(timeZoneID: Self.shanghai)
        let now = date(2026, 9, 30, 12, timeZoneID: Self.shanghai)
        let day1 = date(2026, 9, 27, 9, timeZoneID: Self.shanghai)
        let day2 = date(2026, 9, 29, 9, timeZoneID: Self.shanghai)

        let createdToday = Note(id: UUID(), text: "今晨创建", createdAt: now)
        let dueToday = Note(id: UUID(), text: "三天前创建今晚到期", createdAt: day1, dueDate: date(2026, 9, 30, 18, timeZoneID: Self.shanghai))
        let createdThreeDaysAgo = Note(id: UUID(), text: "三天前创建无到期", createdAt: day1)
        let overdue = Note(id: UUID(), text: "昨天到期已逾期", createdAt: day1, dueDate: day2)
        let dueTomorrow = Note(id: UUID(), text: "今晨创建明天到期", createdAt: now, dueDate: date(2026, 10, 1, 9, timeZoneID: Self.shanghai))
        let doneToday = Note(id: UUID(), text: "今晨创建已勾选", createdAt: now, done: true)

        // 输出保持输入相对顺序(filter 不重排);逾期与陈年便签不进「今日」组。
        #expect(
            NoteEngine.todaysNotes(
                [createdThreeDaysAgo, overdue, dueToday, dueTomorrow, createdToday, doneToday],
                now: now,
                calendar: cal
            ) == [dueToday, dueTomorrow, createdToday, doneToday]
        )
        #expect(NoteEngine.todaysNotes([], now: now, calendar: cal) == [])
    }

    /// 登记项③的决策钉子:done 跨午夜持久保留——引擎没有也不设「跨午夜自动重置」,
    /// 不新增 doneAt 列;午夜只改变「今日」分组(与 W7 喂养结算),绝不改写勾选状态。
    /// (最少意外原则:用户昨晚勾掉的事,不该半夜被系统偷偷"翻开"。w3.v1 设计时复核。)
    @Test func midnightChangesGroupingOnlyAndNeverResetsDone() {
        let cal = makeCalendar(timeZoneID: Self.ny)
        let lateNight = date(2026, 10, 1, 23, 59, timeZoneID: Self.ny)
        let nextMorning = date(2026, 10, 2, 8, 0, timeZoneID: Self.ny)
        let overnight = Note(text: "隔夜事项", createdAt: lateNight, done: true)

        // 午夜前:属于「今日」;午夜后:不再属于「今日」——分组随日界翻转。
        #expect(NoteEngine.todaysNotes([overnight], now: lateNight, calendar: cal) == [overnight])
        #expect(NoteEngine.todaysNotes([overnight], now: nextMorning, calendar: cal) == [])

        // 但 done 原样保留:日界函数(分组/到期)对 done 零改写;无到期也永不因跨夜变逾期。
        #expect(overnight.done == true)
        #expect(NoteEngine.dueStatus(overnight, now: nextMorning, calendar: cal) == .none)
        #expect(NoteEngine.isOverdue(overnight, now: nextMorning, calendar: cal) == false)
    }

    // MARK: - 到期语义:nil/today/overdue/upcoming;「今天」优先于「逾期」

    @Test func dueStatusCoversNoneTodayUpcomingOverdue() {
        let cal = makeCalendar(timeZoneID: Self.ny)
        let now = date(2026, 9, 30, 12, timeZoneID: Self.ny)

        // nil = 未设到期。
        #expect(NoteEngine.dueStatus(
            Note(text: "无到期", createdAt: fixed(1), dueDate: nil), now: now, calendar: cal
        ) == .none)
        // 今天 09:00、现在 12:00:虽已过点,仍算 today——「due today = dueToday」,
        // 当天不得降级为逾期(逾期 = 到期时刻严格早于今日起点)。
        #expect(NoteEngine.dueStatus(
            Note(text: "今晨已过点", createdAt: fixed(1), dueDate: date(2026, 9, 30, 9, timeZoneID: Self.ny)),
            now: now, calendar: cal
        ) == .today)
        #expect(NoteEngine.dueStatus(
            Note(text: "今晚到期", createdAt: fixed(1), dueDate: date(2026, 9, 30, 23, 59, timeZoneID: Self.ny)),
            now: now, calendar: cal
        ) == .today)
        // 明天 → upcoming(哪怕只差一分钟跨日)。
        #expect(NoteEngine.dueStatus(
            Note(text: "明天", createdAt: fixed(1), dueDate: date(2026, 10, 1, 0, 0, timeZoneID: Self.ny)),
            now: now, calendar: cal
        ) == .upcoming)
        // 昨天、一个月前 → overdue。
        #expect(NoteEngine.dueStatus(
            Note(text: "昨天", createdAt: fixed(1), dueDate: date(2026, 9, 29, 23, 59, timeZoneID: Self.ny)),
            now: now, calendar: cal
        ) == .overdue)
        #expect(NoteEngine.dueStatus(
            Note(text: "一个月前", createdAt: fixed(1), dueDate: date(2026, 8, 30, 12, timeZoneID: Self.ny)),
            now: now, calendar: cal
        ) == .overdue)
    }

    /// overdue 的精确定义:dueDate < 今日真实起点(跳变日为 01:00 类)才算;
    /// dueDate == 今日起点属于今天。边界在 DST 跳变日也不含糊。
    @Test func isOverdueMeansDueStrictlyBeforeStartOfToday() {
        let santiago = makeCalendar(timeZoneID: "America/Santiago")
        // 跳变日刚开始半小时(真实时刻 01:30)。
        let now = date(2026, 9, 6, 1, 30, timeZoneID: "America/Santiago")

        // dueDate == 今日起点 01:00 → today,不算逾期。
        let dueAtDayStart = Note(text: "今日起点到期", createdAt: fixed(1), dueDate: date(2026, 9, 6, 1, 0, timeZoneID: "America/Santiago"))
        #expect(NoteEngine.isOverdue(dueAtDayStart, now: now, calendar: santiago) == false)
        #expect(NoteEngine.dueStatus(dueAtDayStart, now: now, calendar: santiago) == .today)

        // dueDate = 昨日最后一刻 → overdue。
        let dueYesterday = Note(text: "昨日到期", createdAt: fixed(1), dueDate: date(2026, 9, 5, 23, 59, timeZoneID: "America/Santiago"))
        #expect(NoteEngine.isOverdue(dueYesterday, now: now, calendar: santiago) == true)

        // 未来 → 不逾期;无到期 → 永不逾期。
        let dueTomorrow = Note(text: "明天到期", createdAt: fixed(1), dueDate: date(2026, 9, 7, 1, 0, timeZoneID: "America/Santiago"))
        #expect(NoteEngine.isOverdue(dueTomorrow, now: now, calendar: santiago) == false)
        #expect(NoteEngine.isOverdue(Note(text: "无到期", createdAt: fixed(1)), now: now, calendar: santiago) == false)
    }
}
