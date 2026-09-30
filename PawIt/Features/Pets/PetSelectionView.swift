import SwiftUI
import Core

/// 宠物选择界面（W6-3）——6 宠物网格，点击选择「当前举牌宠物」。
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
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose your pet companion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 16) {
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
            // 先取消所有选中
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

// MARK: - Pet Card

private struct PetCard: View {
    let species: PetSpecies
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                PetAvatarView(
                    species: species,
                    mood: .neutral,
                    size: 72,
                    pose: .holding
                )
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .frame(width: 72, height: 72)
                    }
                }

                Text(PetAsset.displayName(species: species))
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PetAsset.displayName(species: species)), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
