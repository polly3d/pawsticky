import WidgetKit
import SwiftUI
import Core

struct PawItEntry: TimelineEntry {
    let date: Date
    /// 预计算时间线条目（Core 的 TimelinePlanner 产出，widget 侧仅做映射）。
    let slot: TimelineSlot
}

struct PawItProvider: TimelineProvider {
    /// 纯逻辑的时间线规划器；渲染侧（此处）是 `Date.now` 的唯一使用点（组合根）。
    private let planner = TimelinePlanner()

    private func makeEntry(at date: Date) -> PawItEntry {
        PawItEntry(date: date, slot: planner.entries(now: date)[0])
    }

    func placeholder(in context: Context) -> PawItEntry {
        makeEntry(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PawItEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    /// D3 / PoC C：时间线只含预计算条目（今天 + 明日 00:01 跨午夜兜底），
    /// `policy: .after(明日 00:01)` 是全天唯一一次预算内刷新请求——
    /// 即使它缺席，00:01 条目也正确渲染新的一天。勾选重绘走 intent perform
    /// 的交互式内建行为，与本时间线策略互相独立（见 Core《刷新策略表》）。
    func getTimeline(in context: Context, completion: @escaping (Timeline<PawItEntry>) -> Void) {
        let now = Date.now
        let entries = planner.entries(now: now).map { PawItEntry(date: $0.date, slot: $0) }
        completion(Timeline(entries: entries, policy: .after(planner.nextReloadDate(after: now))))
    }
}

struct PawItWidgetEntryView: View {
    var entry: PawItEntry

    /// 进程内复用的共享库连接（首次渲染打开一次，避免每次重绘重连）。
    /// 容器不可用（如缺 entitlement 的预览环境）时按未勾选渲染。
    private static let store: SharedStore? = try? SharedStore.appGroup()

    /// 渲染时实时读取 App Group 数据库：intent perform 后系统重绘即拿到新值。
    private var isToggled: Bool {
        guard let store = Self.store else { return false }
        return (try? store.firstNoteIsDone()) ?? false
    }

    var body: some View {
        Button(intent: ToggleItemIntent()) {
            VStack(spacing: 6) {
                Image(systemName: isToggled ? "checkmark.circle.fill" : "pawprint")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isToggled ? Color.green : Color.secondary)
                Text(isToggled ? "ON" : "OFF")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("轻点切换")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct PawItWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PawItWidget", provider: PawItProvider()) { entry in
            PawItWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PawIt")
        .description("由你的宠物帮你记住事情")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct PawItWidgetBundle: WidgetBundle {
    var body: some Widget {
        PawItWidget()
    }
}
