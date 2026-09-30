import ActivityKit
import SwiftUI
import WidgetKit
import Core

/// 便签 Live Activity 渲染——钉在锁屏的全宽便签卡片 + Dynamic Island。
struct NoteActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoteActivityAttributes.self) { context in
            // ── 锁屏 / 通知横幅展示（全宽，主战场）──
            LockScreenActivityView(context: context)
                .containerBackground(for: .widget) {
                    noteBackground(context.state.noteStyle)
                }
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Dynamic Island 展开态（4 区域）──
                DynamicIslandExpandedRegion(.leading) {
                    petImage(context.attributes.petSpecies)
                        .frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.noteText.isEmpty
                             ? "Untitled" : context.state.noteText)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .strikethrough(context.state.isDone)

                        if !context.state.items.isEmpty {
                            let done = context.state.items.filter(\.done).count
                            Text("\(done)/\(context.state.items.count) done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.items.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(
                                Array(context.state.items.prefix(3).enumerated()),
                                id: \.offset
                            ) { _, item in
                                HStack(spacing: 4) {
                                    Image(systemName: item.done
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.caption2)
                                        .foregroundStyle(item.done ? .green : .secondary)
                                    Text(item.text)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .strikethrough(item.done)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                // ── 药丸左端：宠物头像 ──
                petImage(context.attributes.petSpecies)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
            } compactTrailing: {
                // ── 药丸右端：便签标题缩略 ──
                Text(context.state.noteText.prefix(12))
                    .font(.caption)
                    .lineLimit(1)
            } minimal: {
                // ── 最小态（多 Activity 时）：爪印 ──
                Image(systemName: "pawprint.fill")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Lock Screen Full-Width Card

/// 锁屏全宽便签卡片——这是 Live Activity 的核心视觉。
/// 布局：左侧宠物（~70pt）| 右侧便签内容 + 清单项。
private struct LockScreenActivityView: View {
    let context: ActivityViewContext<NoteActivityAttributes>

    private var state: NoteActivityAttributes.ContentState { context.state }
    private var attrs: NoteActivityAttributes { context.attributes }
    private var textColor: Color {
        let preset = state.noteStyle ?? "classicYellow"
        return preset == "charcoal"
            ? Color(red: 0.93, green: 0.93, blue: 0.94)
            : Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左侧：宠物图
            VStack {
                Spacer()
                petImage(attrs.petSpecies)
                    .frame(width: 70, height: 70)
                Spacer()
            }

            // 右侧：便签内容
            VStack(alignment: .leading, spacing: 6) {
                // 标题行
                HStack {
                    Text(state.noteText.isEmpty ? "Untitled" : state.noteText)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(textColor)
                        .lineLimit(2)
                        .strikethrough(state.isDone)

                    Spacer(minLength: 4)

                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                // 清单项
                if !state.items.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(
                            Array(state.items.prefix(5).enumerated()),
                            id: \.offset
                        ) { _, item in
                            HStack(spacing: 5) {
                                Image(systemName: item.done
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                    .foregroundStyle(item.done ? .green : textColor.opacity(0.4))
                                Text(item.text)
                                    .font(.caption)
                                    .foregroundStyle(textColor)
                                    .lineLimit(1)
                                    .strikethrough(item.done)
                            }
                        }
                        if state.items.count > 5 {
                            Text("+\(state.items.count - 5) more")
                                .font(.caption2)
                                .foregroundStyle(textColor.opacity(0.5))
                        }
                    }
                }

                Spacer(minLength: 0)

                // 底部：宠物名 + 完成进度
                HStack {
                    Text(attrs.petName)
                        .font(.caption2)
                        .foregroundStyle(textColor.opacity(0.5))
                    Spacer()
                    if !state.items.isEmpty {
                        let done = state.items.filter(\.done).count
                        Text("\(done)/\(state.items.count) done")
                            .font(.caption2.bold())
                            .foregroundStyle(textColor.opacity(0.6))
                    } else if state.isDone {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Shared Helpers

/// 宠物图片（holding 优先，降级到 front）——复用 Widget 的 Asset Catalog。
private func petImage(_ speciesRaw: String) -> some View {
    let holdingName = "pet-\(speciesRaw)-holding"
    let frontName = "pet-\(speciesRaw)-front"
    let hasHolding = (speciesRaw == "cat" || speciesRaw == "corgi")
    let imageName = hasHolding ? holdingName : frontName

    return Image(imageName)
        .resizable()
        .aspectRatio(contentMode: .fit)
}

/// 便签背景色（从 NoteStylePreset rawValue 映射）。
private func noteBackground(_ styleRaw: String?) -> some View {
    let color: Color = {
        switch styleRaw {
        case "classicYellow": return Color(red: 1.0, green: 0.976, blue: 0.769)
        case "mint":          return Color(red: 0.784, green: 0.902, blue: 0.788)
        case "sakura":        return Color(red: 0.984, green: 0.804, blue: 0.863)
        case "ocean":         return Color(red: 0.733, green: 0.871, blue: 0.984)
        case "lavender":      return Color(red: 0.839, green: 0.788, blue: 0.945)
        case "charcoal":      return Color(red: 0.259, green: 0.259, blue: 0.278)
        default:              return Color(red: 1.0, green: 0.976, blue: 0.769)
        }
    }()
    return color
}
