import Testing
import Foundation
@testable import Core

/// GrowthEngine 轻养成逻辑测试（W7-0）。
struct GrowthEngineTests {

    /// 固定时区日历，避免测试结果受设备时区影响。
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        DateComponents(calendar: cal, year: y, month: m, day: d, hour: h).date!
    }

    // MARK: - 首次喂食

    @Test func firstFeedSetsFedLevelAndStreak() {
        let state = GrowthState(petId: "cat")
        let now = date(2026, 11, 1)
        let result = GrowthEngine.feed(state: state, now: now, calendar: cal)

        #expect(result.fedLevel == 1)
        #expect(result.streakDays == 1)
        #expect(result.lastActiveDay == now)
    }

    // MARK: - 同一天多次喂食

    @Test func feedSameDayIncrementsFedLevelButNotStreak() {
        var state = GrowthState(petId: "cat", fedLevel: 3, streakDays: 2)
        state.lastActiveDay = date(2026, 11, 1, 10)

        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 1, 18), calendar: cal)

        #expect(result.fedLevel == 4, "fedLevel should increment")
        #expect(result.streakDays == 2, "streak should NOT increment on same day")
    }

    // MARK: - 连续天数

    @Test func feedConsecutiveDayIncrementsStreak() {
        var state = GrowthState(petId: "cat", fedLevel: 5, streakDays: 3)
        state.lastActiveDay = date(2026, 11, 1)

        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 2), calendar: cal)

        #expect(result.fedLevel == 6)
        #expect(result.streakDays == 4, "streak should increment for consecutive day")
    }

    // MARK: - 断签不惩罚（Finch 原则）

    @Test func feedAfterGapResetStreakButNotFedLevel() {
        var state = GrowthState(petId: "cat", fedLevel: 10, streakDays: 5)
        state.lastActiveDay = date(2026, 11, 1)

        // 跳过 2 天
        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 4), calendar: cal)

        #expect(result.fedLevel == 11, "fedLevel must NEVER decrease")
        #expect(result.streakDays == 1, "streak resets to 1 (today is day 1 of new streak)")
    }

    @Test func feedAfterLongGapStillPreservesFedLevel() {
        var state = GrowthState(petId: "cat", fedLevel: 50, streakDays: 20)
        state.lastActiveDay = date(2026, 1, 1)

        // 10 个月后
        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 1), calendar: cal)

        #expect(result.fedLevel == 51, "fedLevel never punished, even after months")
        #expect(result.streakDays == 1)
    }

    // MARK: - 装扮解锁

    @Test func feedUnlocksOutfitAtThreshold() {
        // bowtie 解锁阈值 = 5，当前 fedLevel = 4
        let state = GrowthState(petId: "cat", fedLevel: 4, streakDays: 1,
                                 lastActiveDay: date(2026, 11, 1))

        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 2), calendar: cal)

        #expect(result.fedLevel == 5)
        let outfits = GrowthEngine.unlockedOutfits(state: result)
        #expect(outfits.contains(.bowtie), "bowtie should unlock at fedLevel 5")
    }

    @Test func feedUnlocksMultipleOutfitsIfJumped() {
        // fedLevel 跳到 10，应该解锁 bowtie(5) 和 topHat(10)
        let state = GrowthState(petId: "cat", fedLevel: 9, streakDays: 1,
                                 lastActiveDay: date(2026, 11, 1))

        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 2), calendar: cal)

        let outfits = GrowthEngine.unlockedOutfits(state: result)
        #expect(outfits.contains(.bowtie))
        #expect(outfits.contains(.topHat))
    }

    @Test func existingOutfitsPreservedOnFeed() {
        let state = GrowthState(petId: "cat", fedLevel: 5, streakDays: 1,
                                 lastActiveDay: date(2026, 11, 1),
                                 unlockedOutfits: "[\"bowtie\"]")

        let result = GrowthEngine.feed(state: state, now: date(2026, 11, 2), calendar: cal)

        let outfits = GrowthEngine.unlockedOutfits(state: result)
        #expect(outfits.contains(.bowtie), "existing outfits must be preserved")
    }

    // MARK: - 进度计算

    @Test func progressToNextOutfitIsZeroAtStart() {
        let state = GrowthState(petId: "cat", fedLevel: 0)
        let progress = GrowthEngine.progressToNextOutfit(state: state)
        #expect(progress >= 0 && progress <= 1)
    }

    @Test func progressToNextOutfitIsOneWhenFullyUnlocked() {
        let json = GrowthEngine.encodeOutfits(Outfit.allCases.map { $0 })
        let state = GrowthState(petId: "cat", fedLevel: 100, unlockedOutfits: json)
        let progress = GrowthEngine.progressToNextOutfit(state: state)
        #expect(progress == 1.0)
    }

    @Test func isFullyUnlockedReturnsTrueWhenAllUnlocked() {
        let json = GrowthEngine.encodeOutfits(Array(Outfit.allCases))
        let state = GrowthState(petId: "cat", unlockedOutfits: json)
        #expect(GrowthEngine.isFullyUnlocked(state: state))
    }

    @Test func isFullyUnlockedReturnsFalseWhenPartial() {
        let state = GrowthState(petId: "cat", unlockedOutfits: "[\"bowtie\"]")
        #expect(!GrowthEngine.isFullyUnlocked(state: state))
    }

    // MARK: - Next Outfit

    @Test func nextOutfitReturnsFirstUnlocked() {
        let state = GrowthState(petId: "cat", fedLevel: 0)
        let next = GrowthEngine.nextOutfit(state: state)
        #expect(next?.outfit == .bowtie)
        #expect(next?.remaining == 5)
    }

    @Test func nextOutfitSkipsAlreadyUnlocked() {
        let state = GrowthState(petId: "cat", fedLevel: 5,
                                 unlockedOutfits: "[\"bowtie\"]")
        let next = GrowthEngine.nextOutfit(state: state)
        #expect(next?.outfit == .topHat)
    }

    @Test func nextOutfitReturnsNilWhenAllUnlocked() {
        let json = GrowthEngine.encodeOutfits(Array(Outfit.allCases))
        let state = GrowthState(petId: "cat", fedLevel: 100, unlockedOutfits: json)
        #expect(GrowthEngine.nextOutfit(state: state) == nil)
    }

    // MARK: - JSON Round-trip

    @Test func outfitJsonRoundTrip() {
        let outfits: [Outfit] = [.bowtie, .crown, .spaceHelmet]
        let json = GrowthEngine.encodeOutfits(outfits)
        let parsed = GrowthEngine.parseOutfits(json)
        #expect(parsed == outfits)
    }

    @Test func parseOutfitsHandlesEmptyString() {
        #expect(GrowthEngine.parseOutfits("[]").isEmpty)
        #expect(GrowthEngine.parseOutfits("").isEmpty)
        #expect(GrowthEngine.parseOutfits("garbage").isEmpty)
    }

    // MARK: - Outfit 阈值

    @Test func outfitThresholdsAreStrictlyIncreasing() {
        let thresholds = Outfit.allCases.map(\.unlockThreshold)
        for i in 1..<thresholds.count {
            #expect(thresholds[i] > thresholds[i - 1],
                    "Thresholds must be strictly increasing")
        }
    }

    @Test func twelveOutfitsExist() {
        #expect(Outfit.allCases.count == 12)
    }

    // MARK: - DST / 时区

    @Test func feedAcrossDSTSpringForwardCountsAsConsecutive() {
        // 2027-03-14 02:00 春令时（NY 时区跳过 02:00→03:00）
        let dayBefore = DateComponents(calendar: cal, year: 2027, month: 3, day: 13, hour: 23).date!
        let dayAfter = DateComponents(calendar: cal, year: 2027, month: 3, day: 14, hour: 10).date!

        var state = GrowthState(petId: "cat", fedLevel: 1, streakDays: 1)
        state.lastActiveDay = dayBefore

        let result = GrowthEngine.feed(state: state, now: dayAfter, calendar: cal)
        #expect(result.streakDays == 2, "DST spring forward should still count as consecutive day")
    }

    @Test func feedAcrossDSTFallBackCountsAsConsecutive() {
        // 2026-11-01 02:00 秋令时（NY 时区回拨 02:00→01:00）
        let dayBefore = DateComponents(calendar: cal, year: 2026, month: 10, day: 31, hour: 23).date!
        let dayAfter = DateComponents(calendar: cal, year: 2026, month: 11, day: 1, hour: 10).date!

        var state = GrowthState(petId: "cat", fedLevel: 1, streakDays: 1)
        state.lastActiveDay = dayBefore

        let result = GrowthEngine.feed(state: state, now: dayAfter, calendar: cal)
        #expect(result.streakDays == 2, "DST fall back should still count as consecutive day")
    }
}
