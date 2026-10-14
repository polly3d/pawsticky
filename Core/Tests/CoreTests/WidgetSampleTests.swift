import Testing
import Foundation
@testable import Core

/// 小组件画廊示例内容的行为钉子。
///
/// 新装用户的库是空的，而「添加小组件」画廊恰好是新用户决定要不要加的时刻——
/// 画廊里必须是一张有内容、有清单、带宠物的便签，而不是空状态。
/// 下面这些断言守的是「示例看起来是好的」：别被改成逾期红字、全勾 / 全未勾、超长换行。
struct WidgetSampleTests {

    /// 几个有代表性的「现在」：清晨、午后、临近午夜（到期时刻会跨日）。
    private let nows: [Date] = {
        let calendar = Calendar(identifier: .gregorian)
        return [(8, 0), (14, 30), (23, 30)].map { hour, minute in
            calendar.date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: 2026, month: 10, day: 14, hour: hour, minute: minute
            ))!
        }
    }()

    // MARK: - 便签本身

    @Test func sampleNoteIsActiveAndNeverOverdue() {
        for now in nows {
            let note = WidgetSample.make(now: now, selectedPet: nil).note
            #expect(!note.done, "示例便签应是待办状态，画廊里要展示「还没做完」的样子")
            #expect(note.dueDate != nil, "带提醒才能展示铃铛 + 倒计时这一行")
            #expect(!NoteEngine.isOverdue(note, now: now), "逾期会渲染成红字，画廊里不该吓人")
        }
    }

    @Test func sampleTextFitsTheSmallWidget() {
        let text = WidgetSample.make(now: nows[0], selectedPet: nil).note.text
        #expect(!text.isEmpty)
        #expect(!text.contains("\n"))
        #expect(text.count <= 32, "小号组件正文最多 3 行，示例不能被截断")
    }

    // MARK: - 清单

    @Test func sampleChecklistMixesDoneAndPending() {
        let sample = WidgetSample.make(now: nows[0], selectedPet: nil)
        #expect(sample.items.count >= 3, "中号组件能放 3 条，示例要把它放满")
        #expect(sample.items.contains { $0.done }, "要有已勾选项，才展示划线样式")
        #expect(sample.items.contains { !$0.done }, "要有未勾选项")
        let fraction = sample.items.completionFraction
        #expect(fraction > 0 && fraction < 1, "锁屏圆环示例要是半满的，而不是空环或满环")
    }

    @Test func sampleItemsBelongToTheSampleNoteInOrder() {
        let sample = WidgetSample.make(now: nows[0], selectedPet: nil)
        #expect(sample.items.allSatisfy { $0.noteId == sample.note.id })
        #expect(sample.items.map(\.position) == Array(0..<sample.items.count), "position 连续递增")
        #expect(Set(sample.items.map(\.id)).count == sample.items.count, "清单项 id 互不相同")
    }

    // MARK: - 稳定性

    @Test func sampleIdentitiesAreStableAcrossCalls() {
        // SwiftUI 靠 id 做 diff / 动画;每次 provider 调用换一批新 id 会让画廊预览闪烁
        let first = WidgetSample.make(now: nows[0], selectedPet: nil)
        let second = WidgetSample.make(now: nows[1], selectedPet: nil)
        #expect(first.note.id == second.note.id)
        #expect(first.items.map(\.id) == second.items.map(\.id))
    }

    // MARK: - 宠物

    @Test func sampleShowsTheUsersSelectedPetWhenThereIsOne() {
        let corgi = PetProfile(
            id: "corgi", species: .corgi,
            displayName: PetAsset.displayName(species: .corgi), isSelected: true
        )
        #expect(WidgetSample.make(now: nows[0], selectedPet: corgi).pet == corgi)
    }

    @Test func sampleFallsBackToTheCatForBrandNewInstalls() {
        let pet = WidgetSample.make(now: nows[0], selectedPet: nil).pet
        #expect(pet.species == .cat, "首发主打宠物是猫")
        #expect(pet.isSelected)
        #expect(pet.displayName == PetAsset.displayName(species: .cat), "名字与全 App 同源")
    }
}
