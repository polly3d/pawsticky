import SwiftUI
import Core

/// 养成仪表盘（W7-2）——展示喂养进度、连击天数、已解锁装扮。
struct GrowthDashboardView: View {
    @State private var growthState: GrowthState?
    @State private var selectedPet: PetProfile?

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    petHeader
                    progressSection
                    outfitGrid
                }
                .padding()
            }
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

    // MARK: - Pet Header

    private var petHeader: some View {
        VStack(spacing: 12) {
            if let pet = selectedPet {
                PetAvatarView(
                    species: pet.species,
                    mood: .neutral,
                    size: 80
                )
                Text(PetAsset.displayName(species: pet.species))
                    .font(.title2.bold())
            } else {
                Image(systemName: "pawprint.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("No pet selected")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        let state = growthState ?? GrowthState(petId: "")

        return VStack(spacing: 16) {
            // 连击
            HStack {
                VStack(alignment: .leading) {
                    Text("Streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(state.streakDays)")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Fed Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(state.fedLevel)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

            // 下一装扮进度
            if let next = GrowthEngine.nextOutfit(state: state) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Next: \(next.outfit.displayName)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(next.remaining) more to go")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: GrowthEngine.progressToNextOutfit(state: state))
                        .tint(.orange)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            } else {
                Text("All outfits unlocked! 🎉")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            }
        }
    }

    // MARK: - Outfit Grid

    private var outfitGrid: some View {
        let unlocked = Set(GrowthEngine.unlockedOutfits(state: growthState ?? GrowthState(petId: "")))
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 12)]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Outfits")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Outfit.allCases, id: \.rawValue) { outfit in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(unlocked.contains(outfit)
                                    ? Color.orange.opacity(0.15)
                                    : Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)

                            if unlocked.contains(outfit) {
                                Image(systemName: outfit.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.title3)
                                    .foregroundStyle(.gray.opacity(0.4))
                            }
                        }

                        Text(outfit.displayName)
                            .font(.caption2)
                            .foregroundStyle(unlocked.contains(outfit) ? .primary : .secondary)
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
