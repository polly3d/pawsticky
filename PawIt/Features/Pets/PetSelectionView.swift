import SwiftUI
import Core

/// 宠物选择界面（W6-3 → W7 升级）——大卡片布局，展示宠物全身。
struct PetSelectionView: View {
    @State private var selectedSpecies: PetSpecies?
    @State private var pets: [PetProfile] = []

    let repository: NoteRepository?
    let onDismiss: () -> Void

    init(repository: NoteRepository? = NoteRepository.cachedAppGroup(), onDismiss: @escaping () -> Void) {
        self.repository = repository
        self.onDismiss = onDismiss
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose your pet companion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(PetSpecies.allCases, id: \.rawValue) { species in
                            PetCard(
                                species: species,
                                isSelected: selectedSpecies == species,
                                onSelect: { selectPet(species) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("My Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task { loadPets() }
    }

    private func loadPets() {
        guard let store = SharedStore.cachedAppGroup() else { return }
        if let selected = try? store.selectedPet() {
            selectedSpecies = selected.species
        }
    }

    private func selectPet(_ species: PetSpecies) {
        guard let store = SharedStore.cachedAppGroup() else { return }
        selectedSpecies = species

        Task {
            for sp in PetSpecies.allCases {
                let pet = PetProfile(
                    id: sp.rawValue,
                    species: sp,
                    displayName: PetAsset.displayName(species: sp),
                    isSelected: sp == species
                )
                try? await store.upsertPet(pet)
            }
        }
    }
}

// MARK: - Pet Card（大卡片布局）

private struct PetCard: View {
    let species: PetSpecies
    let isSelected: Bool
    let onSelect: () -> Void

    private var accentColor: Color {
        Color(
            hue: PetAsset.accentHue(species: species) / 360,
            saturation: 0.5,
            brightness: 0.85
        )
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                // 宠物全身图
                Image("pet-\(species.rawValue)-front")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 100)
                    .padding(.top, 12)

                // 名字
                Text(PetAsset.displayName(species: species))
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? accentColor : .primary)

                // 性格标签
                Text(personality(species))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                        ? accentColor.opacity(0.1)
                        : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(duration: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PetAsset.displayName(species: species)), \(personality(species)), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func personality(_ species: PetSpecies) -> String {
        switch species {
        case .cat:      return "Warm & Playful"
        case .graycat:  return "Calm & Gentle"
        case .corgi:    return "Loyal & Energetic"
        case .shiba:    return "Independent & Bold"
        case .rabbit:   return "Soft & Curious"
        case .hamster:  return "Tiny & Cheerful"
        }
    }
}
