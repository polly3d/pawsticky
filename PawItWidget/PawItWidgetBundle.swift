import WidgetKit
import SwiftUI
import Core

// MARK: - Widget Entry View（路由）

struct PawItWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PawItEntry

    var body: some View {
        // 全部家族从 entry 携带的数据快照渲染（P1-1）——含锁屏三家族，
        // 逾期判定统一用 entry.date（P0-3 口径修正的使能点）。
        switch family {
        case .systemSmall:
            SmallNoteWidget(entry: entry)
        case .systemMedium:
            MediumNoteWidget(entry: entry)
        case .systemLarge:
            LargeNoteWidget(entry: entry)
        case .accessoryCircular:
            CircularLockScreenWidget(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenWidget(entry: entry)
        case .accessoryInline:
            InlineLockScreenWidget(entry: entry)
        default:
            SmallNoteWidget(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct PawItWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PawItWidget", provider: PawItProvider()) { entry in
            PawItWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PawSticky Note")
        .description("Your pet remembers things for you")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Widget Bundle

@main
struct PawItWidgetBundle: WidgetBundle {
    var body: some Widget {
        PawItWidget()
        NoteActivityLiveActivity()
    }
}
