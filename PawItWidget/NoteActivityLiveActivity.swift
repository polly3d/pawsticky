import ActivityKit
import SwiftUI
import WidgetKit
import Core

/// LA 清单项快照接入清单进度单一定义点（P1-3）——
/// `Checkable` 归 Core,此处补 LA DTO 的 conformance（Shared/ 不 import Core）。
extension NoteActivityAttributes.ChecklistItem: Checkable {
    var isDone: Bool { done }
}

/// 便签 Live Activity 渲染——钉在锁屏的全宽便签卡片 + Dynamic Island。
struct NoteActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoteActivityAttributes.self) { context in
            // ── 锁屏 / 通知横幅展示（全宽，主战场）──
            LockScreenActivityView(context: context)
                // C10（第三轮，官方文档口径）：锁屏呈现的背景色由 activityBackgroundTint 管——
                // 默认白（Light）/ 黑（Dark）/ 玻璃（iOS 26），自定义背景必须走这个修饰符；
                // 此前只设 containerBackground（主屏 Widget 的机制），在真机上从未生效，
                // iOS 26 把默认底改成玻璃后彻底暴露（粉彩被剥、文字变系统灰阶）。
                .activityBackgroundTint(noteBackground(context.state.noteStyle))
                // 文档配套要求：自定义背景时，系统"结束 Live Activity"辅助按钮的文字色
                // 也要跟着设（否则可能在粉彩底上低对比）。
                .activitySystemActionForegroundColor(
                    NoteStylePreset.resolve(context.state.noteStyle).textColor
                )
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
                            Text("\(context.state.items.doneCount)/\(context.state.items.count) done")
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
    /// 颜色走 `NoteStylePreset` 单一定义（P0-4 修复）——此前此处硬编码一份 RGB
    /// 副本,与 App/Widget 的预设色天然漂移。
    private var preset: NoteStylePreset { NoteStylePreset.resolve(state.noteStyle) }
    private var textColor: Color { preset.textColor }
    /// 次级文字（宠物名 / 进度 / 未勾图标）——保持墨色家族但对比度优先：
    /// 此前 0.4–0.6 的透明度等效 #8C–#A6 浅灰，caption2 小字号在锁屏真机上看不清（C10）；
    /// charcoal 预设的浅色墨对称适用（深底上的 0.75 浅灰仍可读）。
    private var secondaryTextColor: Color { textColor.opacity(0.75) }

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
                                    .foregroundStyle(item.done ? .green : secondaryTextColor)
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
                                .foregroundStyle(secondaryTextColor)
                        }
                    }
                }

                Spacer(minLength: 0)

                // 底部：宠物名 + 完成进度
                HStack {
                    Text(attrs.petName)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                    Spacer()
                    if !state.items.isEmpty {
                        Text("\(state.items.doneCount)/\(state.items.count) done")
                            .font(.caption2.bold())
                            .foregroundStyle(secondaryTextColor)
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
/// 「哪些物种有举牌图」的裁决在 `PetAsset.hasHoldingPose`（单一事实源），
/// 此前此处与 iOS Widget 各内联一份 cat/corgi 特判。
private func petImage(_ speciesRaw: String) -> some View {
    let imageName: String
    if let species = PetSpecies(rawValue: speciesRaw), PetAsset.hasHoldingPose(species: species) {
        imageName = "pet-\(speciesRaw)-holding"
    } else {
        imageName = "pet-\(speciesRaw)-front"
    }
    return Image(imageName)
        .resizable()
        .aspectRatio(contentMode: .fit)
}

/// 便签背景色（NoteStylePreset 单一定义——此前硬编码 RGB 副本，P0-4 修复）。
private func noteBackground(_ styleRaw: String?) -> Color {
    NoteStylePreset.resolve(styleRaw).backgroundColor
}
