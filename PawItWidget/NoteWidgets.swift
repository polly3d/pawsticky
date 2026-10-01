import WidgetKit
import SwiftUI
import Core

// MARK: - System Small（宠物在右下角，便签文字在上方）

struct SmallNoteWidget: View {
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 便签内容
            VStack(alignment: .leading, spacing: 4) {
                if let note = content.note {
                    noteContent(note)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)

            // 宠物图（右下角，35% 宽度）
            if let pet = content.pet {
                Image(petImageName(pet.species))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 55, height: 55)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
            }
        }
        .containerBackground(for: .widget) {
            content.preset.backgroundColor
        }
    }

    private func noteContent(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(intent: ToggleItemIntent()) {
                Text(note.text.isEmpty ? "Untitled" : note.text)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(content.preset.textColor)
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
                                ? Color.red : content.preset.textColor.opacity(0.7)
                        )
                }
                Spacer()
                let items = content.items
                if !items.isEmpty {
                    Text("\(items.doneCount)/\(items.count)")
                        .font(.caption2)
                        .foregroundStyle(content.preset.textColor.opacity(0.6))
                }
                if content.hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(content.preset.textColor.opacity(0.6))
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
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        HStack(spacing: 0) {
            if let note = content.note {
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
            content.preset.backgroundColor
        }
    }

    private var petArea: some View {
        VStack {
            Spacer()
            if let pet = content.pet {
                Image(petImageName(pet.species))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(content.preset.textColor.opacity(0.3))
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
                    .foregroundStyle(content.preset.textColor)
                    .lineLimit(2)
                    .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Checklist 项
            let items = content.items
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items.prefix(3), id: \.id) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(item.done ? .green : content.preset.textColor.opacity(0.4))
                            Text(item.text)
                                .font(.caption)
                                .foregroundStyle(content.preset.textColor)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                    }
                    if items.count > 3 {
                        Text("+\(items.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(content.preset.textColor.opacity(0.5))
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
                    Text("\(items.doneCount)/\(items.count)")
                        .font(.caption2)
                        .foregroundStyle(content.preset.textColor.opacity(0.5))
                }
                if content.hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(content.preset.textColor.opacity(0.6))
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
            if let pet = content.pet {
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
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 便签主内容
            VStack(alignment: .leading, spacing: 8) {
                if let note = content.note {
                    fullNoteContent(note)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)

            // 宠物在左下角
            if let pet = content.pet {
                Image(petImageName(pet.species))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
            }
        }
        .containerBackground(for: .widget) {
            content.preset.backgroundColor
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
                            .foregroundStyle(content.preset.textColor)
                            .lineLimit(3)
                            .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                        Spacer()
                        Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(note.done ? .green : content.preset.textColor.opacity(0.4))
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
                .background(content.preset.textColor.opacity(0.2))

            // 清单项
            let items = content.items
            if items.isEmpty {
                Text("No checklist items")
                    .font(.caption)
                    .foregroundStyle(content.preset.textColor.opacity(0.5))
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.prefix(8), id: \.id) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline)
                                .foregroundStyle(item.done ? .green : content.preset.textColor.opacity(0.4))
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(content.preset.textColor)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                    }
                    if items.count > 8 {
                        Text("+\(items.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(content.preset.textColor.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            // 底部：日期 + 进度 + 翻页
            HStack {
                Text(note.createdAt.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(content.preset.textColor.opacity(0.5))
                Spacer()
                if !items.isEmpty {
                    Text("\(items.doneCount)/\(items.count) done")
                        .font(.caption2)
                        .foregroundStyle(content.preset.textColor.opacity(0.5))
                }
                if content.hasMultipleNotes {
                    Button(intent: CycleNoteIntent()) {
                        HStack(spacing: 2) {
                            Text("Next")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(content.preset.textColor.opacity(0.6))
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
