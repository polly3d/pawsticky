import Testing
@testable import Core

/// Live Activity 小尺寸卡片（Apple Watch 智能叠放 / CarPlay）“一瞥”逻辑的行为钉子。
///
/// 小卡片最小只有 152×69.5pt，放不下整张清单；只回答三件事：
/// 做到哪了（进度环 + x/y）→ 下一件做什么 → 再后面还有什么。
/// 视图只管画，这里钉住“算什么、怎么算”：进度环比例、下一项 / 后续项的挑选、完成态的判定。
struct ActivityGlanceTests {

    /// 测试替身——真实元素是 Widget 里的 `NoteActivityAttributes.ChecklistItem`。
    private struct Item: TextCheckable {
        let text: String
        let isDone: Bool
        init(_ text: String, done: Bool = false) {
            self.text = text
            self.isDone = done
        }
    }

    // MARK: - 没有清单（普通便签）

    @Test func plainNoteHasNoRingAndIsNotComplete() {
        let glance = ActivityGlance(items: [Item](), noteIsDone: false)
        #expect(glance.total == 0)
        #expect(glance.done == 0)
        #expect(glance.ringFraction == nil)   // nil = 不画进度环，只放大头像
        #expect(glance.isComplete == false)
        #expect(glance.next == nil)
        #expect(glance.upcoming.isEmpty)
    }

    @Test func plainNoteMarkedDoneIsCompleteButStillHasNoRing() {
        let glance = ActivityGlance(items: [Item](), noteIsDone: true)
        #expect(glance.isComplete)
        #expect(glance.ringFraction == nil)
        #expect(glance.next == nil)
    }

    // MARK: - 清单进行中

    @Test func partiallyDoneChecklistReportsProgressAndNextItems() {
        let glance = ActivityGlance(
            items: [Item("Milk", done: true), Item("Eggs"), Item("Bread"), Item("Coffee beans")],
            noteIsDone: false
        )
        #expect(glance.total == 4)
        #expect(glance.done == 1)
        #expect(glance.ringFraction == 0.25)
        #expect(glance.isComplete == false)
        #expect(glance.next == "Eggs")
        #expect(glance.upcoming == ["Bread", "Coffee beans"])
    }

    @Test func untouchedChecklistHasAnEmptyRingNotANilOne() {
        // 0/3 是“有清单但还没开始”（环为空），和“没有清单”（nil、无环）是两回事
        let glance = ActivityGlance(items: [Item("A"), Item("B"), Item("C")], noteIsDone: false)
        #expect(glance.ringFraction == 0)
        #expect(glance.next == "A")
        #expect(glance.upcoming == ["B", "C"])
    }

    @Test func upcomingIsCappedAtTwoByDefault() {
        let glance = ActivityGlance(
            items: [Item("A"), Item("B"), Item("C"), Item("D"), Item("E")],
            noteIsDone: false
        )
        #expect(glance.next == "A")
        #expect(glance.upcoming == ["B", "C"])   // 一瞥而已：下一项 + 最多 2 项
    }

    @Test func upcomingLimitIsConfigurable() {
        let items = [Item("A"), Item("B"), Item("C"), Item("D")]
        #expect(ActivityGlance(items: items, noteIsDone: false, upcomingLimit: 1).upcoming == ["B"])
        #expect(ActivityGlance(items: items, noteIsDone: false, upcomingLimit: 0).upcoming.isEmpty)
    }

    @Test func nextSkipsAlreadyDoneItemsInTheMiddle() {
        // 勾选顺序可以乱：下一项永远是“清单顺序里第一个没勾的”
        let glance = ActivityGlance(
            items: [Item("A", done: true), Item("B"), Item("C", done: true), Item("D"), Item("E")],
            noteIsDone: false
        )
        #expect(glance.done == 2)
        #expect(glance.next == "B")
        #expect(glance.upcoming == ["D", "E"])
    }

    @Test func lastRemainingItemHasNoUpcoming() {
        let glance = ActivityGlance(
            items: [Item("A", done: true), Item("B", done: true), Item("C")],
            noteIsDone: false
        )
        #expect(glance.next == "C")
        #expect(glance.upcoming.isEmpty)
    }

    // MARK: - 完成态

    @Test func allItemsDoneMeansComplete() {
        let glance = ActivityGlance(
            items: [Item("A", done: true), Item("B", done: true)],
            noteIsDone: false
        )
        #expect(glance.isComplete)
        #expect(glance.ringFraction == 1)
        #expect(glance.done == 2)
        #expect(glance.next == nil)
        #expect(glance.upcoming.isEmpty)
    }

    @Test func noteMarkedDoneIsCompleteEvenWithItemsLeft() {
        // 用户直接把整条便签标成已完成：卡片按“完成”画满环，不再提示下一项；
        // done 仍如实反映勾了几项（不篡改）
        let glance = ActivityGlance(
            items: [Item("A", done: true), Item("B"), Item("C")],
            noteIsDone: true
        )
        #expect(glance.isComplete)
        #expect(glance.ringFraction == 1)
        #expect(glance.done == 1)
        #expect(glance.total == 3)
        #expect(glance.next == nil)
        #expect(glance.upcoming.isEmpty)
    }

    // MARK: - 文本清理

    @Test func itemTextIsTrimmed() {
        let glance = ActivityGlance(items: [Item("  Eggs \n"), Item("\tBread  ")], noteIsDone: false)
        #expect(glance.next == "Eggs")
        #expect(glance.upcoming == ["Bread"])
    }

    @Test func blankItemsAreNeverShownAsNextButStillCountInTheTotal() {
        // 空白条目显示成 “Next: ”（后面什么都没有）很怪，所以不当作下一项；
        // 但它确实占一格，进度分母不能少算
        let glance = ActivityGlance(
            items: [Item("   "), Item("Real task"), Item("")],
            noteIsDone: false
        )
        #expect(glance.total == 3)
        #expect(glance.next == "Real task")
        #expect(glance.upcoming.isEmpty)
    }
}
