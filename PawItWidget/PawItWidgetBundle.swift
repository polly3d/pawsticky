import WidgetKit
import SwiftUI
import Core

// MARK: - Timeline Entry

struct PawItEntry: TimelineEntry {
    let date: Date
    let slot: TimelineSlot
}

// MARK: - Timeline Provider

struct PawItProvider: TimelineProvider {
    private let planner = TimelinePlanner()

    func placeholder(in context: Context) -> PawItEntry {
        PawItEntry(date: .now, slot: planner.entries(now: .now)[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (PawItEntry) -> Void) {
        completion(PawItEntry(date: .now, slot: planner.entries(now: .now)[0]))
    }

    /// D3 时间线策略：预计算双条目（今天 + 明日 00:01），每日至多 1 次预算内刷新。
    func getTimeline(in context: Context, completion: @escaping (Timeline<PawItEntry>) -> Void) {
        let now = Date.now
        let entries = planner.entries(now: now).map { PawItEntry(date: $0.date, slot: $0) }
        completion(Timeline(entries: entries, policy: .after(planner.nextReloadDate(after: now))))
    }
}

// MARK: - Widget Entry View（路由）

struct PawItWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: PawItEntry

    private let data = WidgetDataProvider()

    var body: some View {
        switch family {
        case .systemSmall:
            SmallNoteWidget(data: data, entry: entry)
        case .systemMedium:
            MediumNoteWidget(data: data, entry: entry)
        case .systemLarge:
            LargeNoteWidget(data: data, entry: entry)
        case .accessoryCircular:
            CircularLockScreenWidget(data: data)
        case .accessoryRectangular:
            RectangularLockScreenWidget(data: data)
        case .accessoryInline:
            InlineLockScreenWidget(data: data)
        default:
            SmallNoteWidget(data: data, entry: entry)
        }
    }
}

// MARK: - System Small（W5：交互式——点击勾选，长按翻页）

struct SmallNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note {
                noteContent(note)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .containerBackground(for: .widget) {
            preset.backgroundColor
        }
    }

    private func noteContent(_ note: Note) -> some View {
        let pet = data.selectedPet()
        let mood = PetNoteRenderer.inferMood(
            isDone: note.done,
            isOverdue: NoteEngine.isOverdue(note, now: entry.date)
        )

        return VStack(alignment: .leading, spacing: 6) {
            // 便签正文（点击整区域勾选）
            Button(intent: ToggleItemIntent()) {
                Text(note.text.isEmpty ? "Untitled" : note.text)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(preset.textColor)
                    .lineLimit(3)
                    .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // 底部栏：宠物 + 状态 + 翻页
            HStack(spacing: 4) {
                if let pet {
                    WidgetPetAvatar(species: pet.species, mood: mood, size: 22)
                }

                if note.done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                }
                if let due = note.dueDate {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(
                            NoteEngine.isOverdue(note, now: entry.date) ? .red : .orange
                        )
                    Text(due, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(
                            NoteEngine.isOverdue(note, now: entry.date)
                                ? Color.red : preset.textColor.opacity(0.7)
                        )
                }
                Spacer()

                let items = data.noteItems(noteId: note.id)
                if !items.isEmpty {
                    Text("\(items.filter(\.done).count)/\(items.count)")
                        .font(.caption2)
                        .foregroundStyle(preset.textColor.opacity(0.6))
                }

                if hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(preset.textColor.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Tap to add a note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System Medium（W5：左侧勾选 + 右侧清单项可勾选 + 翻页）

struct MediumNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let note {
                leftColumn(note)
                rightColumn(note)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .containerBackground(for: .widget) {
            preset.backgroundColor
        }
    }

    private func leftColumn(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(intent: ToggleItemIntent()) {
                Text(note.text.isEmpty ? "Untitled" : note.text)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(preset.textColor)
                    .lineLimit(4)
                    .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if let due = note.dueDate {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                        Text(due, style: .relative)
                            .font(.caption2)
                    }
                    .foregroundStyle(
                        NoteEngine.isOverdue(note, now: entry.date) ? .red : .orange
                    )
                }
                Spacer()
                if hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(preset.textColor.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func rightColumn(_ note: Note) -> some View {
        let items = data.noteItems(noteId: note.id)
        return VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text("No items")
                    .font(.caption)
                    .foregroundStyle(preset.textColor.opacity(0.5))
            } else {
                ForEach(items.prefix(4), id: \.id) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(item.done ? .green : preset.textColor.opacity(0.5))
                        Text(item.text)
                            .font(.caption)
                            .foregroundStyle(preset.textColor)
                            .lineLimit(1)
                            .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                    }
                }
                if items.count > 4 {
                    Text("+\(items.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(preset.textColor.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Tap to add a note")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System Large（W5：勾选 + 翻页 + 清单项交互）

struct LargeNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note {
                fullNoteContent(note)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .containerBackground(for: .widget) {
            preset.backgroundColor
        }
    }

    private func fullNoteContent(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题（可勾选）
            HStack {
                Button(intent: ToggleItemIntent()) {
                    HStack {
                        Text(note.text.isEmpty ? "Untitled" : note.text)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(preset.textColor)
                            .lineLimit(3)
                            .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                        Spacer()
                        Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(note.done ? .green : preset.textColor.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
            }

            // 到期
            if let due = note.dueDate {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                    Text(due.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption)
                }
                .foregroundStyle(
                    NoteEngine.isOverdue(note, now: entry.date) ? .red : .orange
                )
            }

            Divider()
                .background(preset.textColor.opacity(0.2))

            // 清单项
            let items = data.noteItems(noteId: note.id)
            if items.isEmpty {
                Text("No checklist items")
                    .font(.caption)
                    .foregroundStyle(preset.textColor.opacity(0.5))
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.prefix(8), id: \.id) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(item.done ? .green : preset.textColor.opacity(0.4))
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(preset.textColor)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                    }
                    if items.count > 8 {
                        Text("+\(items.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(preset.textColor.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            // 底部：日期 + 进度 + 翻页
            HStack {
                Text(note.createdAt.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(preset.textColor.opacity(0.5))
                Spacer()
                if !items.isEmpty {
                    Text("\(items.filter(\.done).count)/\(items.count) done")
                        .font(.caption2)
                        .foregroundStyle(preset.textColor.opacity(0.5))
                }
                if hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        HStack(spacing: 2) {
                            Text("Next")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(preset.textColor.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No notes yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open PawIt to create your first note")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lock Screen: Circular

struct CircularLockScreenWidget: View {
    let data: WidgetDataProvider

    private var note: Note? { data.currentNote() }

    var body: some View {
        if let note {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 2) {
                    Image(systemName: note.done ? "checkmark.circle.fill" : "pawprint.fill")
                        .font(.title3)
                    if let due = note.dueDate {
                        Text(due, style: .timer)
                            .font(.system(.caption2, design: .monospaced))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pawprint")
                    .font(.title2)
            }
        }
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularLockScreenWidget: View {
    let data: WidgetDataProvider

    private var note: Note? { data.currentNote() }

    var body: some View {
        if let note {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: note.done ? "checkmark.circle.fill" : "pawprint.fill")
                        .font(.caption)
                    Text(note.text.isEmpty ? "Untitled" : note.text)
                        .font(.headline)
                        .lineLimit(1)
                        .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                }
                let items = data.noteItems(noteId: note.id)
                if !items.isEmpty {
                    ForEach(items.prefix(2), id: \.id) { item in
                        HStack(spacing: 3) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                            Text(item.text)
                                .font(.caption)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                        .foregroundStyle(.secondary)
                    }
                } else if let due = note.dueDate {
                    Text(due, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "pawprint")
                        .font(.caption)
                    Text("PawIt")
                        .font(.headline)
                }
                Text("No notes yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lock Screen: Inline

struct InlineLockScreenWidget: View {
    let data: WidgetDataProvider

    private var note: Note? { data.currentNote() }

    var body: some View {
        if let note {
            let items = data.noteItems(noteId: note.id)
            if !items.isEmpty {
                let done = items.filter(\.done).count
                Text("📝 \(note.text.prefix(20)) (\(done)/\(items.count))")
            } else {
                Text("📝 \(note.text.prefix(30))")
            }
        } else {
            Text("🐾 PawIt — No notes")
        }
    }
}

// MARK: - Widget Configuration

struct PawItWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PawItWidget", provider: PawItProvider()) { entry in
            PawItWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PawIt Note")
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
    }
}
