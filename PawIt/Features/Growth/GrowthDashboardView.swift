import SwiftUI
import Core

/// 养成仪表盘（Soft Companion 风格）——宠物居中 + 进度环 + 装扮网格。
///
/// 升级要点：
/// - 宠物居中大图（120px + idle 动画）
/// - Duolingo 式进度环替代条形进度条
/// - 暖色背景一致性
/// - 装扮网格用暖色调
struct GrowthDashboardView: View {
    @State private var growthState: GrowthState?
    @State private var selectedPet: PetProfile?

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    petCenterStage
                    statsRow
                    progressRing
                    outfitGrid
                }
                .padding()
            }
            .warmBackground()
            .navigationTitle("Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task { loadState() }
    }

    // MARK: - Pet Center Stage

    private var petCenterStage: some View {
        VStack(spacing: 14) {
            if let pet = selectedPet {
                PetAvatarView(
                    species: pet.species,
                    mood: petMood,
                    size: 120,
                    animated: true
                )

                Text(PetAsset.displayName(species: pet.species))
                    .font(AppTheme.title)

                if let gs = growthState, gs.streakDays > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(gs.streakDays) day streak")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Image(systemName: "pawprint.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("No pet selected")
                    .font(AppTheme.subtitle)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    /// 根据 growth 状态决定心情
    private var petMood: PetMood {
        guard let gs = growthState else { return .neutral }
        if gs.streakDays >= 7 { return .happy }
        return .neutral
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let state = growthState ?? GrowthState(petId: "")

        return HStack(spacing: 16) {
            StatBubble(
                value: "\(state.streakDays)",
                label: "Streak Days",
                icon: "flame.fill",
                color: .orange
            )
            StatBubble(
                value: "\(state.fedLevel)",
                label: "Fed Level",
                icon: "heart.fill",
                color: .pink
            )
            StatBubble(
                value: "\(GrowthEngine.unlockedOutfits(state: state).count)",
                label: "Collected",
                icon: "sparkles",
                color: .purple
            )
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        let state = growthState ?? GrowthState(petId: "")
        let progress = GrowthEngine.progressToNextOutfit(state: state)

        return VStack(spacing: 12) {
            if let next = GrowthEngine.nextOutfit(state: state) {
                ZStack {
                    // 背景环
                    Circle()
                        .stroke(AppTheme.separator, lineWidth: 10)
                        .frame(width: 100, height: 100)

                    // 进度环
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.8), value: progress)

                    // 中心文字
                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("to next")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                HStack {
                    Text("Next: \(next.outfit.displayName)")
                        .font(AppTheme.cardTitle)
                    Spacer()
                    Text("\(next.remaining) more to go")
                        .font(AppTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text("Collection complete!")
                    .font(AppTheme.subtitle)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(AppTheme.surfaceBackground)
                .shadow(
                    color: AppTheme.lightShadow.color,
                    radius: AppTheme.lightShadow.radius,
                    y: AppTheme.lightShadow.y
                )
        )
    }

    // MARK: - Outfit Grid

    private var outfitGrid: some View {
        let unlocked = Set(GrowthEngine.unlockedOutfits(state: growthState ?? GrowthState(petId: "")))
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 12)]

        return VStack(alignment: .leading, spacing: 12) {
            // v1.0 没有换装功能：对外一律叫 Collection（决策 A5(a)），preflight 会拦截 outfit 字样
            Text("Collection")
                .font(AppTheme.cardTitle)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Outfit.allCases, id: \.rawValue) { outfit in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppTheme.smallCornerRadius)
                                .fill(unlocked.contains(outfit)
                                    ? Color.orange.opacity(0.12)
                                    : AppTheme.separator.opacity(0.5))
                                .frame(width: 60, height: 60)

                            if unlocked.contains(outfit) {
                                Image(systemName: outfit.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.secondaryText.opacity(0.4))
                            }
                        }

                        Text(outfit.displayName)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(unlocked.contains(outfit) ? .primary : AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .accessibilityLabel("\(outfit.displayName), \(unlocked.contains(outfit) ? "unlocked" : "locked, \(outfit.unlockThreshold) feeds required")")
                }
            }
        }
    }

    // MARK: - Data

    private func loadState() {
        guard let store = SharedStore.cachedAppGroup() else { return }
        selectedPet = try? store.selectedPet()
        if let petId = selectedPet?.id {
            growthState = try? store.growthState(petId: petId)
        }
    }
}

// MARK: - Stat Bubble

private struct StatBubble: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))

            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(AppTheme.surfaceBackground)
                .shadow(
                    color: AppTheme.lightShadow.color,
                    radius: AppTheme.lightShadow.radius,
                    y: AppTheme.lightShadow.y
                )
        )
    }
}
