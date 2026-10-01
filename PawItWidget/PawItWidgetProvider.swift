import WidgetKit
import SwiftUI
import Core

// MARK: - Timeline Entry（P1-1：数据随 entry 进入渲染层）

struct PawItEntry: TimelineEntry {
    let date: Date
    let slot: TimelineSlot
    /// 渲染所需的全部数据——provider 阶段抓取，body 零 DB 查询。
    let content: WidgetContent
}

// MARK: - Timeline Provider

struct PawItProvider: TimelineProvider {
    private let planner = TimelinePlanner()
    private let data = WidgetDataProvider()

    /// 单条目构造：数据抓取与时间线策略在此汇合。
    private func makeEntry(now: Date) -> PawItEntry {
        PawItEntry(
            date: now,
            slot: planner.entries(now: now)[0],
            content: data.fetchContent()
        )
    }

    func placeholder(in context: Context) -> PawItEntry {
        makeEntry(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PawItEntry) -> Void) {
        completion(makeEntry(now: .now))
    }

    /// D3 时间线策略：预计算双条目（今天 + 明日 00:01），每日至多 1 次预算内刷新。
    /// 数据在此时一次抓取；跨午夜条目沿用同一快照（内容变更由 intent/前台 reload 驱动）。
    func getTimeline(in context: Context, completion: @escaping (Timeline<PawItEntry>) -> Void) {
        let now = Date.now
        let content = data.fetchContent()
        let entries = planner.entries(now: now).map {
            PawItEntry(date: $0.date, slot: $0, content: content)
        }
        completion(Timeline(entries: entries, policy: .after(planner.nextReloadDate(after: now))))
    }
}

// MARK: - Pet Image Helper

/// 宠物图片名查找：有举牌资产的物种用 holding，其余降级 front。
/// 「哪些物种能举牌」的裁决在 `PetAsset.hasHoldingPose`（资产层知识，单一事实源）。
func petImageName(_ species: PetSpecies) -> String {
    PetAsset.hasHoldingPose(species: species)
        ? PetAsset.imageName(species: species, pose: .holding)
        : "pet-\(species.rawValue)-front"
}
