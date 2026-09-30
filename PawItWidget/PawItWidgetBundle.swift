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

    var body: some View {
        VStack(spacing: 4) {
            Text("🐾")
                .font(.system(size: 28))
            Text("PawIt")
                .font(.caption.bold())
        }
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
