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

// MARK: - System Small（宠物在右下角，便签文字在上方）

struct SmallNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var pet: PetProfile? { data.selectedPet() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 便签内容
            VStack(alignment: .leading, spacing: 4) {
                if let note {
                    noteContent(note)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

            // 宠物图（右下角，35% 宽度）
            if let pet {
                let petName = petImageName(pet.species)
                Image(petName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 55, height: 55)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
        }
        .containerBackground(for: .widget) {
            preset.backgroundColor
        }
    }

    private func noteContent(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

            // 底部状态栏
            HStack(spacing: 4) {
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

// MARK: - System Medium（宠物在左侧举牌，便签内容在右侧）

struct MediumNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var pet: PetProfile? { data.selectedPet() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        HStack(spacing: 0) {
            if let note {
                // 左侧：宠物区（约 30% 宽度）
                petArea
                    .frame(maxHeight: .infinity)

                // 右侧：便签内容（约 70% 宽度）
                noteArea(note)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            preset.backgroundColor
        }
    }

    private var petArea: some View {
        VStack {
            Spacer()
            if let pet {
                let petName = petImageName(pet.species)
                Image(petName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(preset.textColor.opacity(0.3))
            }
            Spacer()
        }
        .frame(width: 110)
        .padding(.leading, 6)
    }

    private func noteArea(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题（可勾选）
            Button(intent: ToggleItemIntent()) {
                Text(note.text.isEmpty ? "Untitled" : note.text)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(preset.textColor)
                    .lineLimit(2)
                    .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Checklist 项
            let items = data.noteItems(noteId: note.id)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items.prefix(3), id: \.id) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(item.done ? .green : preset.textColor.opacity(0.4))
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(preset.textColor)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                    }
                    if items.count > 3 {
                        Text("+\(items.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(preset.textColor.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            // 底部状态
            HStack(spacing: 4) {
                if note.done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                }
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
                if !items.isEmpty {
                    Text("\(items.filter(\.done).count)/\(items.count)")
                        .font(.caption2)
                        .foregroundStyle(preset.textColor.opacity(0.5))
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
        .padding(.vertical, 14)
        .padding(.trailing, 14)
        .padding(.leading, 4)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            if let pet {
                Image(petImageName(pet.species))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80)
            }
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Tap to add a note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - System Large（宠物在左下角，便签占主区域）

struct LargeNoteWidget: View {
    let data: WidgetDataProvider
    let entry: PawItEntry

    private var note: Note? { data.currentNote() }
    private var pet: PetProfile? { data.selectedPet() }
    private var preset: NoteStylePreset {
        note?.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }
    private var hasMultipleNotes: Bool { data.noteCount() > 1 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 便签主内容
            VStack(alignment: .leading, spacing: 8) {
                if let note {
                    fullNoteContent(note)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)

            // 宠物在左下角
            if let pet {
                Image(petImageName(pet.species))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
            }
        }
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
    private var pet: PetProfile? { data.selectedPet() }

    var body: some View {
        if let note {
            ZStack {
                AccessoryWidgetBackground()
                if let pet {
                    // 真实宠物头像 + 状态角标
                    ZStack {
                        petImage(pet)
                            .clipShape(Circle())

                        // 状态角标
                        if note.done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                                .background(Circle().fill(.black).frame(width: 16, height: 16))
                                .offset(x: 14, y: 14)
                        } else if note.dueDate != nil, NoteEngine.isOverdue(
                            note, now: .now
                        ) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .background(Circle().fill(.black).frame(width: 16, height: 16))
                                .offset(x: 14, y: 14)
                        }
                    }
                } else {
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
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                if let pet {
                    petImage(pet)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "pawprint")
                        .font(.title2)
                }
            }
        }
    }

    @ViewBuilder
    private func petImage(_ pet: PetProfile) -> some View {
        Image("pet-\(pet.species.rawValue)-front")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .widgetAccentable()
    }
}

// MARK: - Lock Screen: Rectangular

struct RectangularLockScreenWidget: View {
    let data: WidgetDataProvider

    private var note: Note? { data.currentNote() }
    private var pet: PetProfile? { data.selectedPet() }

    var body: some View {
        if let note {
            HStack(spacing: 8) {
                // 左侧：宠物头像
                if let pet {
                    petImage(pet)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // 右侧：便签内容
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.text.isEmpty ? "Untitled" : note.text)
                        .font(.headline)
                        .lineLimit(1)
                        .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                        .widgetAccentable()

                    let items = data.noteItems(noteId: note.id)
                    if !items.isEmpty {
                        HStack(spacing: 3) {
                            let doneCount = items.filter(\.done).count
                            Text("\(doneCount)/\(items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // 进度条
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.secondary.opacity(0.3))
                                        .frame(height: 4)
                                    Capsule()
                                        .fill(.primary)
                                        .frame(
                                            width: geo.size.width * CGFloat(doneCount) / CGFloat(max(items.count, 1)),
                                            height: 4
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                    } else if let due = note.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: NoteEngine.isOverdue(note, now: .now) ? "exclamationmark.triangle.fill" : "bell.fill")
                                .font(.caption2)
                            Text(due, style: .relative)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } else if note.done {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("Done")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                if let pet {
                    petImage(pet)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "pawprint")
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PawIt")
                        .font(.headline)
                        .widgetAccentable()
                    Text("No notes yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func petImage(_ pet: PetProfile) -> some View {
        Image("pet-\(pet.species.rawValue)-front")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .widgetAccentable()
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
                Label {
                    Text("\(note.text.prefix(18)) \(done)/\(items.count)")
                } icon: {
                    Image(systemName: "pawprint.fill")
                }
            } else if note.done {
                Label {
                    Text("✓ \(note.text.prefix(25))")
                } icon: {
                    Image(systemName: "pawprint.fill")
                }
            } else {
                Label {
                    Text("\(note.text.prefix(28))")
                } icon: {
                    Image(systemName: "pawprint.fill")
                }
            }
        } else {
            Label("PawIt — No notes", systemImage: "pawprint")
        }
    }
}

// MARK: - Pet Image Helper

/// 宠物图片名查找：holding pose → front 降级。
/// cat/corgi 有举牌图，其余用正面图。
private func petImageName(_ species: PetSpecies) -> String {
    let holdingName = PetAsset.imageName(species: species, pose: .holding)
    switch species {
    case .cat, .corgi:
        return holdingName
    default:
        return "pet-\(species.rawValue)-front"
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
