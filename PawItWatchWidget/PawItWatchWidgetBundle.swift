import WidgetKit
import SwiftUI
import Core

// MARK: - Timeline

struct WatchNoteEntry: TimelineEntry {
    let date: Date
    /// 当前轮播到的单条便签（nil = 无数据 / 全部完成）。
    let note: WatchPayload.NoteSnapshot?
    let pet: WatchPayload.PetSnapshot?
    /// 未完成便签总数（用于角标 / 分页指示器）。
    let pendingCount: Int
    /// 当前便签在轮播队列中的位置（1-based）。
    let noteIndex: Int
    /// 所有便签是否都已完成。
    let allDone: Bool
}

struct WatchNoteProvider: TimelineProvider {

    func placeholder(in context: Context) -> WatchNoteEntry {
        WatchNoteEntry(date: .now, note: nil, pet: nil,
                       pendingCount: 0, noteIndex: 0, allDone: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchNoteEntry) -> Void) {
        let payload = Self.loadPayload()
        let pending = payload?.notes.filter { !$0.done } ?? []
        let first = pending.first.map { Self.sortItems($0) }
        completion(WatchNoteEntry(
            date: .now, note: first, pet: payload?.selectedPet,
            pendingCount: pending.count, noteIndex: pending.isEmpty ? 0 : 1,
            allDone: payload != nil && pending.isEmpty
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNoteEntry>) -> Void) {
        let payload = Self.loadPayload()
        let pending = (payload?.notes ?? []).filter { !$0.done }

        // 全部完成或无数据 → 单条 "All done" 或空状态
        guard !pending.isEmpty else {
            let entry = WatchNoteEntry(
                date: .now, note: nil, pet: payload?.selectedPet,
                pendingCount: 0, noteIndex: 0,
                allDone: payload != nil && !(payload?.notes.isEmpty ?? true)
            )
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
            return
        }

        // 每条未完成便签一个 Entry，间隔 5 分钟轮播
        var entries: [WatchNoteEntry] = []
        for (i, raw) in pending.enumerated() {
            let note = Self.sortItems(raw)
            let entryDate = Calendar.current.date(byAdding: .minute, value: 5 * i, to: .now)!
            entries.append(WatchNoteEntry(
                date: entryDate, note: note, pet: payload?.selectedPet,
                pendingCount: pending.count, noteIndex: i + 1,
                allDone: false
            ))
        }

        // 轮播完毕后 30 分钟刷新
        let lastDate = entries.last!.date
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: lastDate)!
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    // MARK: - Helpers

    /// 从 App Group UserDefaults 读取 iPhone 同步的快照。
    private static func loadPayload() -> WatchPayload? {
        let defaults = UserDefaults(suiteName: PawItInfo.appGroupID)
        guard let data = defaults?.data(forKey: "com.pawit.watchPayload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    /// 未完成的清单项排到前面，已完成的放后面。
    private static func sortItems(_ note: WatchPayload.NoteSnapshot) -> WatchPayload.NoteSnapshot {
        let sorted = note.items.sorted { !$0.done && $1.done }
        return WatchPayload.NoteSnapshot(
            id: note.id, text: note.text, done: note.done,
            dueDate: note.dueDate, style: note.style, items: sorted
        )
    }
}

// MARK: - Widget Views

/// Smart Stack 矩形 Widget（accessoryRectangular）——Watch 主力展示。
/// 每次轮播一条未完成便签，未完成清单项优先展示。
struct WatchRectangularWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let note = entry.note {
            VStack(alignment: .leading, spacing: 2) {
                // 标题行：宠物 + 便签名 + 分页指示
                HStack(spacing: 4) {
                    if let pet = entry.pet {
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

                    Spacer(minLength: 0)

                    // 分页指示 "1/3"
                    if entry.pendingCount > 1 {
                        Text("\(entry.noteIndex)/\(entry.pendingCount)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // 清单项（未完成优先，最多显示 3 条）
                if !note.items.isEmpty {
                    let pendingItems = note.items.filter { !$0.done }
                    let display = pendingItems.isEmpty ? Array(note.items.prefix(3)) : Array(pendingItems.prefix(3))

                    ForEach(Array(display.enumerated()), id: \.offset) { _, item in
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

                    let remaining = pendingItems.count - display.count
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if entry.allDone {
            // 全部完成状态
            VStack(spacing: 4) {
                if let pet = entry.pet {
                    Image("pet-\(pet.species)-front")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .widgetAccentable()
                }
                Text("All done!")
                    .font(.system(.caption, weight: .bold))
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
/// 显示当前便签的清单完成进度环。
struct WatchCircularWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if let note = entry.note {
            let items = note.items
            let progress: Double = items.isEmpty
                ? 0.0
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

                if let pet = entry.pet {
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
        } else if entry.allDone {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .widgetAccentable()
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
        if let note = entry.note {
            if !note.items.isEmpty {
                let pending = note.items.filter { !$0.done }.count
                Label("\(note.text.prefix(12)) · \(pending) left",
                      systemImage: "pawprint.fill")
            } else {
                Label("\(note.text.prefix(20))", systemImage: "pawprint.fill")
            }
        } else if entry.allDone {
            Label("All done!", systemImage: "checkmark.seal.fill")
        } else {
            Label("PawIt", systemImage: "pawprint")
        }
    }
}

/// 角落 Widget（accessoryCorner）——watchOS 专属。
/// 显示未完成便签数。
struct WatchCornerWidget: View {
    let entry: WatchNoteEntry

    var body: some View {
        if entry.pendingCount > 0 {
            Image(systemName: "pawprint.fill")
                .font(.title3)
                .widgetLabel {
                    Text("\(entry.pendingCount) left")
                }
        } else if entry.allDone {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .widgetLabel { Text("Done") }
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
