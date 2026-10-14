import SwiftUI
import Core

/// 宠物选择界面（Soft Companion 风格）——仅用于非 onboarding 场景的"换宠"。
///
/// Onboarding 场景已由 OnboardingView 接管。此处保留日常「My Pet」入口，
/// 升级为暖色背景 + 弹跳动效 + 对话气泡反馈。
struct PetSelectionView: View {
    @State private var selectedSpecies: PetSpecies?
    @State private var bouncing: PetSpecies?

    let repository: NoteRepository?
    let onDismiss: () -> Void

    init(
        repository: NoteRepository? = NoteRepository.cachedAppGroup(),
        isOnboarding: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.repository = repository
        self.onDismiss = onDismiss
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose your pet companion")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(PetSpecies.allCases, id: \.rawValue) { species in
                            PetCard(
                                species: species,
                                isSelected: selectedSpecies == species,
                                isBouncing: bouncing == species,
                                onSelect: { selectPet(species) }
                            )
                        }
                    }
                    .padding(.horizontal)

                    // 选中后的对话反馈
                    if let species = selectedSpecies {
                        PetDialogueBubble(
                            text: PetDialogue.switched(species),
                            maxWidth: 260
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .padding(.top, 8)
                    }
                }
                .padding(.top)
            }
            .warmBackground()
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

        // 弹跳反馈
        withAnimation(AppTheme.petHappyAnimation) {
            selectedSpecies = species
            bouncing = species
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            bouncing = nil
        }

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

// MARK: - Pet Card（Soft Companion 风格）

private struct PetCard: View {
    let species: PetSpecies
    let isSelected: Bool
    let isBouncing: Bool
    let onSelect: () -> Void

    private var accentColor: Color {
        AppTheme.petAccentColor(species: species)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image("pet-\(species.rawValue)-front")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 90)
                    .padding(.top, 14)
                    .scaleEffect(isBouncing ? 1.15 : (isSelected ? 1.05 : 1.0))
                    .offset(y: isBouncing ? -8 : 0)
                    .animation(AppTheme.petHappyAnimation, value: isBouncing)
                    .animation(.spring(duration: 0.3), value: isSelected)

                Text(PetAsset.displayName(species: species))
                    .font(AppTheme.cardTitle)
                    .foregroundStyle(isSelected ? accentColor : .primary)

                Text(personality(species))
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(isSelected
                        ? accentColor.opacity(0.1)
                        : AppTheme.surfaceBackground)
                    .shadow(
                        color: isSelected ? accentColor.opacity(0.2) : AppTheme.cardShadow.color,
                        radius: isSelected ? 12 : AppTheme.cardShadow.radius,
                        y: AppTheme.cardShadow.y
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .strokeBorder(
                        isSelected ? accentColor : Color.clear,
                        lineWidth: 2.5
                    )
            )
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
