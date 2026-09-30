import WidgetKit
import SwiftUI
import Core

// MARK: - Timeline

struct WatchNoteEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?
}

struct WatchNoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNoteEntry {
        WatchNoteEntry(date: .now, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchNoteEntry) -> Void) {
        completion(WatchNoteEntry(date: .now, payload: Self.loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNoteEntry>) -> Void) {
        let entry = WatchNoteEntry(date: .now, payload: Self.loadPayload())
        let nextReload = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }

    /// 直接从 App Group UserDefaults 读取 iPhone 同步的快照。
    /// 与 WatchSessionManager 使用相同的存储键和 App Group。
    private static func loadPayload() -> WatchPayload? {
        let defaults = UserDefaults(suiteName: PawItInfo.appGroupID)
        guard let data = defaults?.data(forKey: "com.pawit.watchPayload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }
}

// MARK: - Widget Views

/// Smart Stack 矩形 Widget（accessoryRectangular）——Watch 主力展示。
struct WatchRectangularWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let payload = entry.payload, let note = payload.notes.first {
            VStack(alignment: .leading, spacing: 2) {
                // 标题行：宠物 + 便签名
                HStack(spacing: 4) {
                    if let pet = payload.selectedPet {
                        Image("pet-\(pet.species)-front")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 12))
                    }
                    Text(note.text.isEmpty ? "Untitled" : note.text)
                        .font(.system(.caption, weight: .bold))
                        .lineLimit(1)
                        .widgetAccentable()
                }

                // 清单项 or 状态
                if !note.items.isEmpty {
                    ForEach(Array(note.items.prefix(2).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 3) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(item.done ? .green : .secondary)
                            Text(item.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .strikethrough(item.done)
                        }
                    }
                    if note.items.count > 2 {
                        Text("+\(note.items.count - 2) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(note.done ? "✓ Done" : "\(payload.notes.count) notes")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // 空状态
            VStack(spacing: 4) {
                Image(systemName: "pawprint.fill")
                    .font(.caption)
                Text("PawIt")
                    .font(.system(.caption, weight: .bold))
                    .widgetAccentable()
                Text("Open iPhone app")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 圆形 Widget（accessoryCircular）——表盘 Complication。
struct WatchCircularWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let payload = entry.payload, let note = payload.notes.first {
            let items = note.items
            let progress: Double = items.isEmpty
                ? (note.done ? 1.0 : 0.0)
                : Double(items.filter(\.done).count) / Double(max(items.count, 1))

            ZStack {
                AccessoryWidgetBackground()

                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 3))
                    .opacity(0.2)
                    .padding(2)

                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .widgetAccentable()
                }

                if let pet = payload.selectedPet {
                    Image("pet-\(pet.species)-front")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(Circle())
                        .padding(8)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 16))
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pawprint")
                    .font(.title3)
            }
        }
    }
}

/// 内联 Widget（accessoryInline）——表盘简洁文字。
struct WatchInlineWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let payload = entry.payload, let note = payload.notes.first {
            if !note.items.isEmpty {
                let done = note.items.filter(\.done).count
                Label("\(note.text.prefix(15)) \(done)/\(note.items.count)",
                      systemImage: "pawprint.fill")
            } else {
                Label("\(note.text.prefix(20))", systemImage: "pawprint.fill")
            }
        } else {
            Label("PawIt", systemImage: "pawprint")
        }
    }
}

/// 角落 Widget（accessoryCorner）——watchOS 专属。
struct WatchCornerWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let payload = entry.payload, !payload.notes.isEmpty {
            Image(systemName: "pawprint.fill")
                .font(.title3)
                .widgetLabel {
                    Text("\(payload.notes.count)")
                }
        } else {
            Image(systemName: "pawprint")
                .font(.title3)
        }
    }
}

// MARK: - Widget 路由

struct WatchWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchNoteEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            WatchRectangularWidget(entry: entry)
        case .accessoryCircular:
            WatchCircularWidget(entry: entry)
        case .accessoryInline:
            WatchInlineWidget(entry: entry)
        case .accessoryCorner:
            WatchCornerWidget(entry: entry)
        default:
            WatchRectangularWidget(entry: entry)
        }
    }
}

// MARK: - Widget 定义

struct PawItWatchNoteWidget: Widget {
    let kind = "PawItWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchNoteProvider()) { entry in
            WatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PawIt Note")
        .description("Your pet remembers things for you")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Widget Bundle

@main
struct PawItWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PawItWatchNoteWidget()
    }
}
