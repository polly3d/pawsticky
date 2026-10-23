import ActivityKit
import SwiftUI
import WidgetKit
import Core

/// LA 清单项快照接入清单进度单一定义点（P1-3）——
/// `Checkable` / `TextCheckable` 归 Core,此处补 LA DTO 的 conformance（Shared/ 不 import Core）。
/// `TextCheckable` 比 `Checkable` 多要一个 `text`（小卡片要亮出“下一件做什么”），`text` 本就是存储属性。
extension NoteActivityAttributes.ChecklistItem: TextCheckable {
    var isDone: Bool { done }
}

/// 便签 Live Activity 渲染——钉在锁屏的全宽便签卡片 + Dynamic Island + 手表 / CarPlay 小卡片。
struct NoteActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoteActivityAttributes.self) { context in
            // ── 按家族选界面：锁屏 / 通知横幅（全宽，主战场）与手表智能叠放 / CarPlay（小卡片）──
            // 没声明 `.small` 时，系统用灵动岛紧凑态的左右小视图拼手表卡片，又小又丑；
            // 声明后手表 / CarPlay 改用主内容闭包，由 `ActivityFamilyRouter` 按家族分流。
            ActivityFamilyRouter(context: context)
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
                // 必须用 badge 档位（≤144px）：系统归档 Live Activity 画面时会按呈现形式的尺寸
                // 卡图片上限，超限不报错、只静默换成灰色占位图——Watch 智能叠放上的灰圆盘就是它
                // （日志 "Max size exceeded: 437.85x219.6; using placeholder image"，此前这里
                // 用的是 480px 的举牌图）。上限由 scripts/preflight.sh 守住。
                PetBadge(speciesRaw: context.attributes.petSpecies, size: 24)
            } compactTrailing: {
                // ── 药丸右端：便签标题缩略（按词边界 + 省略号，口径见 Core 的 LiveActivityText）──
                compactTitleText(context.state.noteText)
                    .font(.caption)
                    .lineLimit(1)
            } minimal: {
                // ── 最小态（多 Activity 时）：爪印 ──
                Image(systemName: "pawprint.fill")
                    .font(.caption)
            }
        }
        .supplementalSmallIfAvailable()
    }
}

extension WidgetConfiguration {
    /// 在 iOS 18+ 声明 `.small` 家族（手表智能叠放 / CarPlay）；iOS 17 没有这个 API，原样返回。
    ///
    /// 部署目标是 iOS 17，而 `supplementalActivityFamilies` 是 iOS 18 才有的。`Widget.body` 不是 result
    /// builder、`WidgetBundleBuilder` 也只认 `if #available`（没有 else），所以没法在调用处写分支；
    /// 但 Swift 允许“不透明返回类型的底层类型随 `#available` 变化”（Apple 自家的
    /// `contentMarginsDisabled()` 向后兼容写法就是这样），于是一个 Widget 就够，不用拆成两个类型。
    func supplementalSmallIfAvailable() -> some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return supplementalActivityFamilies([.small])
        } else {
            return self
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

// MARK: - 家族路由（锁屏大卡片 vs 手表 / CarPlay 小卡片）

/// 按 Live Activity 家族选界面：`.small`（手表智能叠放 / CarPlay）→ 小卡片；其余 → 锁屏大卡片。
///
/// `@Environment(\.activityFamily)` 是 iOS 18 才有的，所以读它的视图单独标 `@available`；
/// iOS 17 一律走锁屏大卡片（那里没有 `.small`，手表仍显示灵动岛紧凑态——见 `PetBadge` 的说明）。
private struct ActivityFamilyRouter: View {
    let context: ActivityViewContext<NoteActivityAttributes>

    var body: some View {
        if #available(iOS 18.0, *) {
            FamilyAwareActivityView(context: context)
        } else {
            LockScreenActivityView(context: context)
        }
    }
}

@available(iOS 18.0, *)
private struct FamilyAwareActivityView: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<NoteActivityAttributes>

    var body: some View {
        switch family {
        case .small:
            SmallActivityView(state: context.state, attrs: context.attributes)
        case .medium:
            LockScreenActivityView(context: context)
        @unknown default:
            LockScreenActivityView(context: context)
        }
    }
}

// MARK: - Small Card（Apple Watch 智能叠放 / CarPlay）

/// Live Activity 的 `.small` 家族——手表智能叠放卡片与 CarPlay 共用。
///
/// 画布很小（手表最小 152×69.5pt，CarPlay 最小 170×78pt），所以只放“一瞥”（算法见 Core 的 `ActivityGlance`）：
///
///     ╭──╮
///     │🐱│  Groceries          环 = 清单完成度，胶囊 = x/y，右上角 = 钉住
///     ╰1/4╯  Next: Eggs         普通便签没有环：头像放大、正文最多 3 行
///            then Bread, Coffee…   画布太矮时从最后一行开始丢
///
/// **没有按钮**——CarPlay 里 Live Activity 的按钮会被禁用；手表上点整张卡片就是“打开”。
/// 底色沿用便签色：除了顶层的 `activityBackgroundTint`，这里还自己铺一层同色底——
/// 万一系统在手表上不认 tint，深色文字也不会落在黑底上看不见。
private struct SmallActivityView: View {
    let state: NoteActivityAttributes.ContentState
    let attrs: NoteActivityAttributes
    private let glance: ActivityGlance

    init(state: NoteActivityAttributes.ContentState, attrs: NoteActivityAttributes) {
        self.state = state
        self.attrs = attrs
        self.glance = ActivityGlance(items: state.items, noteIsDone: state.isDone)
    }

    private var preset: NoteStylePreset { NoteStylePreset.resolve(state.noteStyle) }
    private var textColor: Color { preset.textColor }
    private var secondaryTextColor: Color { textColor.opacity(0.7) }

    var body: some View {
        HStack(spacing: 8) {
            PetProgressRing(
                speciesRaw: attrs.petSpecies,
                glance: glance,
                textColor: textColor,
                cardColor: preset.backgroundColor
            )
            VStack(alignment: .leading, spacing: 2) {
                if glance.ringFraction == nil {
                    plainNoteText
                } else {
                    checklistText
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(preset.backgroundColor.ignoresSafeArea())
        // 画布是固定的，系统字号放得再大也塞不下——封顶在 .large，再挤就靠 minimumScaleFactor 兜底
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .combine)
    }

    // MARK: 清单便签：标题 + “Next: …” + “then …”

    /// 画布矮就从下往上丢行：全部 → 去掉 “then …” → 只剩标题。
    private var checklistText: some View {
        ViewThatFits(in: .vertical) {
            checklistLines(showUpcoming: true)
            checklistLines(showUpcoming: false)
            titleLine
        }
    }

    private func checklistLines(showUpcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            titleLine
            if glance.isComplete {
                Label("All done!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                if showUpcoming {
                    Text(completionSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            } else {
                if let next = glance.next {
                    HStack(spacing: 3) {
                        Text("Next:")
                            .foregroundStyle(secondaryTextColor)
                            .layoutPriority(1)   // 标签不被挤掉，截断的是后面的条目文字
                        Text(next)
                            .foregroundStyle(textColor)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                }
                if showUpcoming, !glance.upcoming.isEmpty {
                    Text("then \(glance.upcoming.joined(separator: ", "))")
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 完成态的第三行。整条便签被直接标成完成、清单却没勾完时，不能再说 “n of n checked off”。
    private var completionSummary: LocalizedStringKey {
        glance.done == glance.total
            ? "\(glance.total) of \(glance.total) checked off"
            : "Marked as done"
    }

    private var titleLine: some View {
        noteTitle(LiveActivityText.firstLine(state.noteText))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(textColor)
            .strikethrough(state.isDone)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: 普通便签：正文本身就是内容

    /// 没有清单时整段正文就是便签的全部内容，不能只取首行：最多放 3 行，画布矮就退到 2 行、1 行。
    private var plainNoteText: some View {
        ViewThatFits(in: .vertical) {
            plainLines(3)
            plainLines(2)
            plainLines(1)
        }
    }

    private func plainLines(_ lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 全是空白的正文按“空便签”处理（显示 Untitled），而不是画一块空白
            noteTitle(LiveActivityText.firstLine(state.noteText).isEmpty ? "" : state.noteText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(textColor)
                .strikethrough(state.isDone)
                .lineLimit(lines)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
            if glance.isComplete {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
    }
}

/// 宠物 + 进度环：环绕头像的环按清单完成度填充，下沿的胶囊写 x/y（完成时换成对勾）；
/// 没有清单（普通便签）就不画环、头像放大。钉住图标挂在右上角、环的外侧——
/// 不占文字的横向空间，三种状态位置一致。
private struct PetProgressRing: View {
    let speciesRaw: String
    let glance: ActivityGlance
    let textColor: Color
    /// 计数胶囊的底色：取卡片背景色，胶囊才像“嵌”在环上，而不是浮在上面。
    let cardColor: Color

    /// 环外径。最矮的画布只有 69.5pt（40mm），减去上下 8pt 内边距后只剩 53.5pt，
    /// 还要给下沿突出的胶囊留位置，所以取 42。
    private let diameter: CGFloat = 42
    private let lineWidth: CGFloat = 4

    /// 进度色取物种主色（与 `PetBadge` / 主屏 Widget 同一套色相）。
    private var accent: Color {
        let hue = PetSpecies(rawValue: speciesRaw).map { PetAsset.accentHue(species: $0) } ?? 30
        return Color(hue: hue / 360, saturation: 0.75, brightness: 0.85)
    }

    var body: some View {
        ZStack {
            if let fraction = glance.ringFraction {
                Circle()
                    .stroke(textColor.opacity(0.15), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        glance.isComplete ? Color.green : accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))   // 从 12 点钟方向顺时针填
                PetBadge(speciesRaw: speciesRaw, size: diameter - 2 * lineWidth - 4)
            } else {
                PetBadge(speciesRaw: speciesRaw, size: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottom) {
            countBadge.offset(y: 3)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(45))
                .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private var countBadge: some View {
        if glance.ringFraction != nil {
            if glance.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green))
            } else {
                Text("\(glance.done)/\(glance.total)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(cardColor))
                    .overlay(Capsule().stroke(textColor.opacity(0.18), lineWidth: 0.5))
            }
        }
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

/// 宠物小头像：物种淡色圆底 + 胸像（85%，耳尖不会被圆形裁掉）。
///
/// 只加载 `pet-<sp>-badge`（48/96/144px）——紧凑态 / 手表小呈现的图片尺寸上限很低，
/// 超限会被系统换成灰色占位图，见 `art/scripts/export-pet-imagesets.sh` 的说明。
/// 圆底配色与主屏 Widget 的 `WidgetPetAvatar` 保持一致（同一套物种色相）。
private struct PetBadge: View {
    let speciesRaw: String
    let size: CGFloat

    private var hue: Double {
        PetSpecies(rawValue: speciesRaw).map { PetAsset.accentHue(species: $0) } ?? 30
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hue: hue / 360, saturation: 0.2, brightness: 0.97))
            Image("pet-\(speciesRaw)-badge")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.85, height: size * 0.85)
        }
        .frame(width: size, height: size)
    }
}

/// 便签标题文本：空便签显示 "Untitled"（与锁屏卡片一致）；用户文字走 verbatim，不当作本地化 key。
@ViewBuilder
private func noteTitle(_ title: String) -> some View {
    if title.isEmpty {
        Text("Untitled")
    } else {
        Text(verbatim: title)
    }
}

/// 紧凑态标题：走 `LiveActivityText` 的缩略口径（词边界 + 省略号）。
private func compactTitleText(_ raw: String) -> some View {
    noteTitle(LiveActivityText.compactTitle(raw))
}
