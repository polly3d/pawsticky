import SwiftUI
import Core

/// IG Story 分享卡片（W7-4）——1080×1920 导出为 UIImage。
///
/// 布局：顶部宠物 + 进度，中部便签内容，底部水印。
/// 设计定位：用户截图/导出分享时保留品牌识别。
struct ShareCardView: View {

    let note: Note
    let pet: PetProfile?
    let growthState: GrowthState?

    /// 卡片渲染尺寸（IG Story 标准）。
    static let cardSize = CGSize(width: 1080, height: 1920)
    /// 缩略图预览尺寸。
    static let previewSize = CGSize(width: 270, height: 480)

    var body: some View {
        ZStack {
            // 背景
            cardBackground

            VStack(spacing: 40) {
                Spacer()
                    .frame(height: 80)

                // 宠物区
                petSection
                    .padding(.horizontal, 60)

                // 便签内容
                noteSection
                    .padding(.horizontal, 60)

                // 进度条
                if let gs = growthState {
                    progressSection(gs)
                        .padding(.horizontal, 60)
                }

                Spacer()

                // 水印
                watermark
                    .padding(.bottom, 40)
            }
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    }

    // MARK: - Background

    private var cardBackground: some View {
        let preset = NoteStylePreset.resolve(note.style)
        return RoundedRectangle(cornerRadius: 0)
            .fill(
                LinearGradient(
                    colors: [preset.backgroundColor, preset.backgroundColor.opacity(0.6), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    // MARK: - Pet Section

    private var petSection: some View {
        HStack(spacing: 24) {
            if let pet {
                PetAvatarView(
                    species: pet.species,
                    mood: .happy,
                    size: 120
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(PetAsset.displayName(species: pet.species))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    if let gs = growthState {
                        Text("🔥 \(gs.streakDays) day streak")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(note.text.isEmpty ? "Untitled" : note.text)
                .font(.system(size: 42, weight: .semibold))
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .strikethrough(note.done)
                .foregroundStyle(note.done ? .secondary : .primary)

            if note.done {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Done!")
                        .foregroundStyle(.green)
                }
                .font(.system(size: 28, weight: .medium))
            }

            if let due = note.dueDate {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                    Text(due.formatted(.dateTime.month().day().hour().minute()))
                }
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        )
    }

    // MARK: - Progress

    private func progressSection(_ gs: GrowthState) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Level \(gs.fedLevel)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                let unlocked = GrowthEngine.unlockedOutfits(state: gs).count
                Text("\(unlocked)/\(Outfit.allCases.count) outfits")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange)
                        .frame(
                            width: geo.size.width * GrowthEngine.progressToNextOutfit(state: gs),
                            height: 16
                        )
                }
            }
            .frame(height: 16)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Watermark

    private var watermark: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 20))
            Text("PawIt")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.secondary.opacity(0.6))
    }

    // MARK: - Export

    /// 将卡片渲染为 UIImage（1080×1920）。
    @MainActor
    static func renderImage(
        note: Note,
        pet: PetProfile?,
        growthState: GrowthState?
    ) -> UIImage? {
        let view = ShareCardView(note: note, pet: pet, growthState: growthState)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0  // 1080×1920 已经是目标分辨率
        return renderer.uiImage
    }
}
