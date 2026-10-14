import SwiftUI
import Core

/// 便签列表——App 主界面（Soft Companion 风格重设计）。
///
/// 核心变更（vs 原 W3-2）：
/// - 暖奶油色背景（AppTheme.background）替代系统白
/// - 宠物头部区更大（64px + idle 动画 + 对话气泡）
/// - 便签行改为卡片式布局（圆角 + 阴影 + 预设色背景）
/// - 空状态使用宠物 + 对话引导替代系统 ContentUnavailableView
/// - Onboarding 路由到新 OnboardingView（fullScreenCover）
struct NoteListView: View {

    @State private var notes: [Note] = []
    @State private var headerPet: PetProfile?
    @State private var headerGrowth: GrowthState?
    @State private var editorMode: EditorMode?
    @State private var showPetSelection = false
    @State private var showGrowthDashboard = false
    @State private var showSettings = false
    @State private var shareNote: Note?

    // Onboarding
    @State private var showOnboarding = false
    @State private var onboardingInProgress = false
    @State private var showWidgetHint = false

    /// Deep link 入口
    @State var deepLinkNoteID: UUID?

    let repository: NoteRepository?

    init(repository: NoteRepository? = NoteRepository.cachedAppGroup()) {
        self.repository = repository
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Widget 添加引导
                    if showWidgetHint {
                        widgetHintBanner
                            .padding(.horizontal, 16)
                    }

                    // Pet Companion Header
                    petHeader
                        .padding(.horizontal, 16)

                    // Notes
                    if notes.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    } else {
                        noteCards
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .warmBackground()
            .navigationTitle("PawSticky")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button { showPetSelection = true } label: {
                            Image(systemName: "pawprint.circle.fill")
                                .font(.title3)
                        }
                        .accessibilityLabel("Choose Pet")

                        Button { showGrowthDashboard = true } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.title3)
                        }
                        .accessibilityLabel("Growth Dashboard")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                        .accessibilityLabel("Settings")

                        Button { editorMode = .create } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                        .accessibilityLabel("New Note")
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NoteEditorView(mode: mode, repository: repository) {
                    reloadNotes()
                    NoteChangeCoordinator.noteChanged(noteId: mode.noteID)
                    finishOnboardingIfNeeded()
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    showOnboarding = false
                    onboardingInProgress = true
                    reloadNotes()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        editorMode = .create
                    }
                }
            }
            .sheet(isPresented: $showPetSelection) {
                PetSelectionView {
                    showPetSelection = false
                    reloadNotes()
                    NoteChangeCoordinator.noteChanged(noteId: nil)
                }
            }
            .sheet(isPresented: $showGrowthDashboard) {
                GrowthDashboardView {
                    showGrowthDashboard = false
                    reloadNotes()
                }
            }
            .sheet(item: $shareNote) { note in
                ShareCardSheet(note: note) { shareNote = nil }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView { showSettings = false }
            }
        }
        .task {
            reloadNotes()
            startOnboardingIfNeeded()
        }
        .onChange(of: deepLinkNoteID) { _, noteID in
            guard let noteID else { return }
            editorMode = .edit(noteID)
            deepLinkNoteID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawItOpenNote)) { notif in
            if let noteID = notif.userInfo?["noteID"] as? UUID {
                editorMode = .edit(noteID)
            }
        }
    }

    // MARK: - Pet Companion Header（更大、更有存在感）

    @ViewBuilder
    private var petHeader: some View {
        if let pet = headerPet {
            Button { showGrowthDashboard = true } label: {
                HStack(spacing: 14) {
                    PetAvatarView(
                        species: pet.species,
                        mood: moodForHeader,
                        size: 64,
                        animated: true
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(PetAsset.displayName(species: pet.species))
                            .font(AppTheme.cardTitle)
                            .foregroundStyle(.primary)

                        if GrowthSettings.isEnabled,
                           let gs = headerGrowth {
                            HStack(spacing: 10) {
                                if gs.streakDays > 0 {
                                    Label("\(gs.streakDays)d streak", systemImage: "flame.fill")
                                        .font(AppTheme.caption)
                                        .foregroundStyle(.orange)
                                }
                                Label("Lv.\(gs.fedLevel)", systemImage: "heart.fill")
                                    .font(AppTheme.caption)
                                    .foregroundStyle(.pink)
                            }
                        }

                        // 宠物对话——根据状态显示不同台词
                        Text(petGreeting)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .italic()
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .fill(AppTheme.petTintBackground(species: pet.species))
                        .shadow(
                            color: AppTheme.lightShadow.color,
                            radius: AppTheme.lightShadow.radius,
                            y: AppTheme.lightShadow.y
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// 根据便签状态决定宠物心情
    private var moodForHeader: PetMood {
        let overdueCount = notes.filter { NoteEngine.isOverdue($0, now: .now) }.count
        if overdueCount > 0 { return .worried }
        let doneToday = notes.filter { $0.done }.count
        if doneToday > 0 { return .happy }
        return .neutral
    }

    /// 宠物随机/状态性台词
    private var petGreeting: String {
        let overdueCount = notes.filter { NoteEngine.isOverdue($0, now: .now) }.count
        if overdueCount > 0 {
            return "You have \(overdueCount) overdue note\(overdueCount > 1 ? "s" : "")..."
        }
        if notes.isEmpty {
            return "What should I remember today?"
        }
        let greetings = [
            "Ready to help!",
            "Let's get things done!",
            "I've got your notes safe.",
            "Tap + to add more!",
        ]
        return greetings[notes.count % greetings.count]
    }

    // MARK: - Empty State（宠物引导风格）

    private var emptyState: some View {
        VStack(spacing: 20) {
            if let pet = headerPet {
                PetAvatarView(
                    species: pet.species,
                    mood: .neutral,
                    size: 100,
                    animated: true
                )

                PetDialogueBubble(
                    text: "No notes yet! Tap + to write your first one, and I'll remember it for you.",
                    maxWidth: 280
                )
            } else {
                Image(systemName: "note.text")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.secondaryText)

                Text("No Notes Yet")
                    .font(AppTheme.subtitle)
            }

            Button { editorMode = .create } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Your First Note")
                }
                .font(AppTheme.cardTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .fill(Color.orange)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Note Cards（卡片式替代 List）

    private var noteCards: some View {
        VStack(spacing: 12) {
            ForEach(notes, id: \.id) { note in
                NoteCardView(
                    note: note,
                    isPinned: LiveActivityManager.isPinned(noteId: note.id),
                    onTap: { editorMode = .edit(note.id) },
                    onToggleDone: { toggleDone(note) },
                    onTogglePin: { togglePin(note) },
                    onDelete: { deleteNote(note) },
                    onShare: { shareNote = note }
                )
            }
        }
    }

    // MARK: - Widget Hint Banner（Soft Companion 风格）

    private var widgetHintBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add PawSticky to Your Home Screen")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("Touch and hold your Home Screen, tap +, then find PawSticky.")
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Button("Got it") {
                OnboardingGate.widgetHintShown = true
                withAnimation { showWidgetHint = false }
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(Color.orange.opacity(0.1))
                .shadow(
                    color: AppTheme.lightShadow.color,
                    radius: AppTheme.lightShadow.radius,
                    y: AppTheme.lightShadow.y
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Onboarding

    private func startOnboardingIfNeeded() {
        guard let store = SharedStore.cachedAppGroup() else { return }
        let hasPet = ((try? store.selectedPet()) ?? nil) != nil
        let count = (try? store.countNotes()) ?? 0
        if OnboardingGate.shouldShowOnboarding(hasSelectedPet: hasPet, noteCount: count) {
            showOnboarding = true
        }
    }

    private func finishOnboardingIfNeeded() {
        guard onboardingInProgress else { return }
        onboardingInProgress = false
        if !notes.isEmpty, !OnboardingGate.widgetHintShown {
            withAnimation { showWidgetHint = true }
        }
    }

    // MARK: - Actions

    private func deleteNote(_ note: Note) {
        guard let repository else { return }
        let reminderManager = ReminderManager()
        Task {
            try? await repository.deleteNote(id: note.id)
            await reminderManager.cancelReminder(noteID: note.id)
            NoteChangeCoordinator.noteDeleted(noteId: note.id)
            reloadNotes()
        }
    }

    private func toggleDone(_ note: Note) {
        guard let repository else { return }
        Task {
            let nowDone = try? await repository.toggleNote(id: note.id)
            if nowDone == true {
                await feedPet()
            }
            reloadNotes()
            NoteChangeCoordinator.noteChanged(noteId: note.id)
        }
    }

    private func togglePin(_ note: Note) {
        if LiveActivityManager.isPinned(noteId: note.id) {
            LiveActivityManager.unpin(noteId: note.id)
        } else {
            guard let store = SharedStore.cachedAppGroup() else { return }
            let items = (try? store.noteItems(noteId: note.id)) ?? []
            let pet = try? store.selectedPet()
            try? LiveActivityManager.pin(note: note, items: items, pet: pet)
        }
    }

    private func feedPet() async {
        guard let store = SharedStore.cachedAppGroup(),
              let pet = try? store.selectedPet(),
              GrowthSettings.isEnabled
        else { return }
        _ = try? await store.feedPet(petId: pet.id)
    }

    func reloadNotes() {
        if let repository {
            notes = (try? repository.allNotes()) ?? []
        }
        if let store = SharedStore.cachedAppGroup() {
            headerPet = try? store.selectedPet()
            headerGrowth = headerPet.flatMap { try? store.growthState(petId: $0.id) }
        }
    }
}

// MARK: - EditorMode

enum EditorMode: Identifiable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let uuid): return uuid.uuidString
        }
    }

    var noteID: UUID? {
        switch self {
        case .create: return nil
        case .edit(let uuid): return uuid
        }
    }
}

// MARK: - Note Card View（卡片式便签行）

struct NoteCardView: View {
    let note: Note
    let isPinned: Bool
    let onTap: () -> Void
    let onToggleDone: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    private var preset: NoteStylePreset {
        NoteStylePreset.resolve(note.style)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 标题行
                HStack {
                    Text(displayTitle)
                        .font(AppTheme.body)
                        .lineLimit(2)
                        .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                        .foregroundStyle(note.done ? .secondary : preset.textColor)

                    Spacer()

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                // 状态行
                HStack(spacing: 8) {
                    if note.done {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(AppTheme.badge)
                            .foregroundStyle(.green)
                    }

                    if let due = note.dueDate {
                        Label(
                            due.formatted(.dateTime.month().day().hour().minute()),
                            systemImage: "bell.fill"
                        )
                        .font(AppTheme.badge)
                        .foregroundStyle(
                            NoteEngine.isOverdue(note, now: .now) ? .red : .orange
                        )
                    }

                    Spacer()

                    Text(note.createdAt.formatted(.dateTime.month().day()))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(preset.textColor.opacity(0.5))
                }
            }
            .noteCard(preset: preset)
        }
        .pressable()
        .contextMenu {
            Button { onToggleDone() } label: {
                Label(note.done ? "Undo" : "Done",
                      systemImage: note.done ? "arrow.uturn.backward" : "checkmark")
            }
            Button { onTogglePin() } label: {
                Label(isPinned ? "Unpin" : "Pin",
                      systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
            }
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var displayTitle: String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        return String(trimmed.prefix(80))
    }

    private var accessibilityDescription: String {
        var parts = [displayTitle]
        if note.done { parts.append("completed") }
        if let due = note.dueDate {
            let status = NoteEngine.isOverdue(note, now: .now) ? "overdue" : "due"
            parts.append("\(status) \(due.formatted(.dateTime.month().day()))")
        }
        return parts.joined(separator: ", ")
    }
}
