import WidgetKit
import SwiftUI
import Core

struct PawItEntry: TimelineEntry {
    let date: Date
}

struct PawItProvider: TimelineProvider {
    func placeholder(in context: Context) -> PawItEntry {
        PawItEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PawItEntry) -> Void) {
        completion(PawItEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PawItEntry>) -> Void) {
        let entry = PawItEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
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
