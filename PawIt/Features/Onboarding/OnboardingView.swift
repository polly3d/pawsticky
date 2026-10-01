import SwiftUI
import Core

/// Soft Companion Onboarding（方案 B）——三步情感引导。
///
/// Step 1: 欢迎页——宠物从底部"走入"，对话气泡问候
/// Step 2: 选宠——卡片布局 + 选中后宠物弹跳 + 个性对话
/// Step 3: 完成 → dismiss，由 NoteListView 接力打开编辑器
///
/// 设计原则：
/// - 宠物是主角，不是装饰
/// - 每一步只做一件事（progressive disclosure）
/// - 对话气泡让宠物"说话"（SyncUP PETS V2 验证）
/// - 整体暖奶油色调（AppTheme.background）
struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var selectedSpecies: PetSpecies?
    @State private var petEntered = false
    @State private var showBubble = false
    @State private var petBounce = false

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // 暖色渐变背景
            backgroundGradient
                .ignoresSafeArea()

            switch step {
            case .welcome:
                welcomeStep
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .selectPet:
                selectPetStep
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(AppTheme.pageTransition, value: step)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                AppTheme.background,
                selectedSpecies.map { AppTheme.petTintBackground(species: $0) } ?? AppTheme.background,
                AppTheme.background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // 对话气泡（先于宠物淡入）
            if showBubble {
                PetDialogueBubble(
                    text: "Hi! I'll remember things for you. Let's pick your companion!",
                    maxWidth: 260
                )
                .transition(.opacity.combined(with: .offset(y: -10)))
                .padding(.bottom, 16)
            }

            // 宠物入场（从底部滑入）
            Image("pet-cat-front")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
                .offset(y: petEntered ? 0 : 200)
                .opacity(petEntered ? 1 : 0)

            Spacer()
                .frame(height: 60)

            // 标题区
            VStack(spacing: 12) {
                Text("Welcome to PawIt")
                    .font(AppTheme.largeTitle)
                    .multilineTextAlignment(.center)

                Text("Your pet remembers things for you")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .opacity(petEntered ? 1 : 0)

            Spacer()
                .frame(height: 40)

            // CTA 按钮
            Button {
                withAnimation(AppTheme.pageTransition) {
                    step = .selectPet
                }
            } label: {
                Text("Let's Go!")
                    .font(AppTheme.cardTitle)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .fill(Color.orange)
                    )
            }
            .padding(.horizontal, 40)
            .opacity(showBubble ? 1 : 0)

            Spacer()
                .frame(height: 60)
        }
        .onAppear {
            // 动画序列：宠物入场 → 停顿 → 气泡淡入
            withAnimation(.spring(duration: 0.8, bounce: 0.3)) {
                petEntered = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showBubble = true
                }
            }
        }
    }

    // MARK: - Step 2: Select Pet

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    private var selectPetStep: some View {
        VStack(spacing: 0) {
            // 标题
            VStack(spacing: 8) {
                Text("Choose Your Companion")
                    .font(AppTheme.title)

                Text("They'll be by your side every day")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.top, 60)
            .padding(.bottom, 24)

            // 宠物网格
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(PetSpecies.allCases, id: \.rawValue) { species in
                        OnboardingPetCard(
                            species: species,
                            isSelected: selectedSpecies == species,
                            onSelect: { selectPet(species) }
                        )
                    }
                }
                .padding(.horizontal, 20)

                // 选中后的对话气泡
                if let species = selectedSpecies {
                    PetDialogueBubble(
                        text: selectionDialogue(species),
                        maxWidth: 280
                    )
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                Spacer()
                    .frame(height: 100)
            }

            // 底部 CTA
            if selectedSpecies != nil {
                Button {
                    confirmSelection()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Together")
                            .font(AppTheme.cardTitle)
                        Image(systemName: "arrow.right")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .fill(selectedSpecies.map { AppTheme.petAccentColor(species: $0) } ?? Color.orange)
                    )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Actions

    private func selectPet(_ species: PetSpecies) {
        guard let store = SharedStore.cachedAppGroup() else { return }
        withAnimation(AppTheme.petHappyAnimation) {
            selectedSpecies = species
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

    private func confirmSelection() {
        onComplete()
    }

    private func selectionDialogue(_ species: PetSpecies) -> String {
        switch species {
        case .cat:     return "Mochi is ready to help! Warm & playful, just for you."
        case .graycat: return "Luna will keep things calm and organized for you."
        case .corgi:   return "Coco can't wait to get started! So much energy!"
        case .shiba:   return "Hachi will remember everything. Count on it."
        case .rabbit:  return "Mimi is curious about what you'll write first!"
        case .hamster: return "Tiny but mighty! Peanut's got your back."
        }
    }
}

// MARK: - Step Enum

private enum OnboardingStep {
    case welcome
    case selectPet
}

// MARK: - Onboarding Pet Card

private struct OnboardingPetCard: View {
    let species: PetSpecies
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var bouncing = false

    private var accentColor: Color {
        AppTheme.petAccentColor(species: species)
    }

    var body: some View {
        Button(action: {
            onSelect()
            // 选中弹跳
            bouncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                bouncing = false
            }
        }) {
            VStack(spacing: 8) {
                Image("pet-\(species.rawValue)-front")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 90)
                    .padding(.top, 14)
                    .scaleEffect(bouncing ? 1.15 : (isSelected ? 1.05 : 1.0))
                    .offset(y: bouncing ? -8 : 0)
                    .animation(AppTheme.petHappyAnimation, value: bouncing)
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
