import WidgetKit
import SwiftUI
import Core

// MARK: - Lock Screen: Circular（宠物头像 + 进度环）

struct CircularLockScreenWidget: View {
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        if let note = content.note {
            // 无清单：完成即满环，未完成为空环；有清单：done/count 比例。
            let progress = content.items.isEmpty
                ? (note.done ? 1.0 : 0.0)
                : content.items.completionFraction

            ZStack {
                AccessoryWidgetBackground()

                // 底层环（始终可见，作为轨道）
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 3))
                    .opacity(0.2)
                    .padding(2)

                // 进度环（填充部分）
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .widgetAccentable()
                }

                // 中心：宠物头像
                if let pet = content.pet {
                    Image("pet-\(pet.species.rawValue)-front")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(Circle())
                        .padding(7)
                } else {
                    Image(systemName: note.done ? "checkmark" : "pawprint.fill")
                        .font(.system(size: 18, weight: .medium))
                }
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                if let pet = content.pet {
                    Image("pet-\(pet.species.rawValue)-front")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(Circle())
                        .padding(7)
                } else {
                    Image(systemName: "pawprint")
                        .font(.title2)
                }
            }
        }
    }
}

// MARK: - Lock Screen: Rectangular（便签卡片——对标 Sticky Widgets）

struct RectangularLockScreenWidget: View {
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        if let note = content.note {
            let items = content.items

            VStack(alignment: .leading, spacing: 1) {
                // 标题行：宠物小图标 + 便签标题
                HStack(spacing: 4) {
                    if let pet = content.pet {
                        Image("pet-\(pet.species.rawValue)-front")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 10))
                    }

                    Text(note.text.isEmpty ? "Untitled" : note.text)
                        .font(.system(.subheadline, weight: .bold))
                        .lineLimit(1)
                        .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                        .widgetAccentable()

                    Spacer(minLength: 0)

                    if note.done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                    }
                }

                // 内容区：清单项 > 到期日 > 创建日期+状态
                if !items.isEmpty {
                    // 有清单项：显示清单列表
                    ForEach(items.prefix(3), id: \.id) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                            Text(item.text)
                                .font(.caption)
                                .lineLimit(1)
                                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                        }
                        .foregroundStyle(item.done ? .secondary : .primary)
                    }

                    if items.count > 3 {
                        Text("+\(items.count - 3) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else if let due = note.dueDate {
                    // 没有清单项，显示到期时间
                    // 口径修正（P0-3）：逾期判定用 entry.date（条目时刻）——
                    // 此前误用 .now,跨午夜条目接管渲染后判定口径与其它家族分裂。
                    Spacer(minLength: 2)
                    HStack(spacing: 4) {
                        Image(systemName: NoteEngine.isOverdue(note, now: entry.date)
                            ? "exclamationmark.triangle.fill" : "bell.fill")
                            .font(.system(size: 10))
                        Text(due, style: .relative)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    // 纯文字便签：显示创建日期 + 便签总数
                    Spacer(minLength: 2)
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(note.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)

                        if content.noteCount > 1 {
                            HStack(spacing: 3) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 9))
                                Text("\(content.noteCount) notes")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            // 空状态
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let pet = content.pet {
                        Image("pet-\(pet.species.rawValue)-front")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 10))
                    }
                    Text("PawIt")
                        .font(.system(.subheadline, weight: .bold))
                        .widgetAccentable()
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
    let entry: PawItEntry

    private var content: WidgetContent { entry.content }

    var body: some View {
        if let note = content.note {
            let items = content.items
            if !items.isEmpty {
                Label {
                    Text("\(note.text.prefix(18)) \(items.doneCount)/\(items.count)")
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
