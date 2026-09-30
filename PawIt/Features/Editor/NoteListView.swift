import SwiftUI
import Core

/// 便签列表——App 主界面（W3-2）。
///
/// 设计原则（来自竞品差评的反面教训）：
/// - "+" 一键创建，sheet 弹出编辑器，光标直达正文，无命名步骤
/// - 创建与编辑共用同一 sheet 编辑器
/// - 排序消费 `allNotes()`——与 Widget/store 同族同序
/// - deep link：通知 tap → 自动打开对应便签（W3-5）
struct NoteListView: View {

    @State private var notes: [Note] = []
    @State private var editorMode: EditorMode?
    @State private var showPetSelection = false
    @State private var showGrowthDashboard = false
    @State private var showSettings = false
    @State private var shareNote: Note?

    /// Deep link 入口：通知 tap 后的目标 noteID（W3-5）。
    @State var deepLinkNoteID: UUID?

    let repository: NoteRepository?

    init(repository: NoteRepository? = NoteRepository.cachedAppGroup()) {
        self.repository = repository
    }

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .navigationTitle("PawIt")
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
                        }
                        .accessibilityLabel("New Note")
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                NoteEditorView(mode: mode, repository: repository) {
                    reloadNotes()
                }
            }
            .sheet(isPresented: $showPetSelection) {
                PetSelectionView {
                    showPetSelection = false
                    reloadNotes()
                }
            }
            .sheet(isPresented: $showGrowthDashboard) {
                GrowthDashboardView { showGrowthDashboard = false }
            }
            .sheet(item: $shareNote) { note in
                ShareCardSheet(note: note) { shareNote = nil }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView { showSettings = false }
            }
        }
        .task { reloadNotes() }
        .task { LiveActivityManager.renewIfNeeded() }
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

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Notes Yet", systemImage: "note.text")
        } description: {
            Text("Tap + to start writing")
        } actions: {
            Button("Create Your First Note") { editorMode = .create }
                .buttonStyle(.borderedProminent)
        }
    }

    private var noteList: some View {
        List {
            // Pet Mascot Header
            petHeader
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

            ForEach(notes, id: \.id) { note in
                Button { editorMode = .edit(note.id) } label: {
                    HStack {
                        NoteRowView(note: note)
                        if LiveActivityManager.isPinned(noteId: note.id) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .tint(.primary)
                .listRowBackground(presetFor(note).backgroundColor.opacity(0.25))
                .swipeActions(edge: .leading) {
                    Button {
                        toggleDone(note)
                    } label: {
                        Label(note.done ? "Undo" : "Done",
                              systemImage: note.done ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(note.done ? .gray : .green)

                    Button {
                        togglePin(note)
                    } label: {
                        Label(
                            LiveActivityManager.isPinned(noteId: note.id) ? "Unpin" : "Pin",
                            systemImage: LiveActivityManager.isPinned(noteId: note.id)
                                ? "pin.slash.fill" : "pin.fill"
                        )
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteNote(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        shareNote = note
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.orange)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .refreshable { reloadNotes() }
    }

    // MARK: - Pet Header

    @ViewBuilder
    private var petHeader: some View {
        if let store = SharedStore.cachedAppGroup(),
           let pet = try? store.selectedPet() {
            Button { showGrowthDashboard = true } label: {
                HStack(spacing: 12) {
                    PetAvatarView(species: pet.species, mood: .neutral, size: 52)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(PetAsset.displayName(species: pet.species))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        if GrowthSettings.isEnabled,
                           let gs = try? store.growthState(petId: pet.id) {
                            HStack(spacing: 8) {
                                if gs.streakDays > 0 {
                                    Label("\(gs.streakDays)d streak", systemImage: "flame.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Label("Lv.\(gs.fedLevel)", systemImage: "heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(.pink)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func presetFor(_ note: Note) -> NoteStylePreset {
        note.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }

    // MARK: - Actions

    private func deleteNotes(at offsets: IndexSet) {
        guard let repository else { return }
        let toDelete = offsets.map { notes[$0] }
        let reminderManager = ReminderManager()
        Task {
            for note in toDelete {
                try? await repository.deleteNote(id: note.id)
                await reminderManager.cancelReminder(noteID: note.id)
            }
            reloadNotes()
        }
    }

    private func deleteNote(_ note: Note) {
        guard let repository else { return }
        let reminderManager = ReminderManager()
        Task {
            try? await repository.deleteNote(id: note.id)
            await reminderManager.cancelReminder(noteID: note.id)
            reloadNotes()
        }
    }

    /// 勾选便签 + 喂食逻辑（W7-3）。
    /// 当 toggle 结果 = done → 触发 GrowthEngine.feed → 持久化。
    private func toggleDone(_ note: Note) {
        guard let repository else { return }
        Task {
            let nowDone = try? await repository.toggleNote(id: note.id)
            if nowDone == true {
                await feedPet()
            }
            reloadNotes()
            // 同步更新锁屏 Live Activity
            if LiveActivityManager.isPinned(noteId: note.id),
               let store = SharedStore.cachedAppGroup(),
               let updatedNotes = try? store.allNotes(),
               let updated = updatedNotes.first(where: { $0.id == note.id }) {
                let items = (try? store.noteItems(noteId: note.id)) ?? []
                LiveActivityManager.updateIfPinned(note: updated, items: items)
            }
        }
    }

    /// 钉/取消钉便签到锁屏 Live Activity。
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

    /// 喂养宠物：读 GrowthState → feed → 写回。
    private func feedPet() async {
        guard let store = SharedStore.cachedAppGroup(),
              let pet = try? store.selectedPet(),
              GrowthSettings.isEnabled
        else { return }

        let current = (try? store.growthState(petId: pet.id)) ?? GrowthState(petId: pet.id)
        let updated = GrowthEngine.feed(state: current, now: .now)
        try? await store.upsertGrowthState(updated)
    }

    func reloadNotes() {
        guard let repository else { return }
        notes = (try? repository.allNotes()) ?? []
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
}

// MARK: - Note Row

struct NoteRowView: View {
    let note: Note

    private var preset: NoteStylePreset {
        note.style.flatMap { NoteStylePreset(rawValue: $0) } ?? .classicYellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(.body)
                .lineLimit(2)
                .strikethrough(NoteEngine.strikethrough(isDone: note.done))
                .foregroundStyle(note.done ? .secondary : .primary)
            HStack(spacing: 8) {
                if note.done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                if let due = note.dueDate {
                    Label(due.formatted(.dateTime.month().day().hour().minute()),
                          systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(
                            NoteEngine.isOverdue(note, now: .now) ? .red : .orange
                        )
                }
                Spacer()
                Text(note.createdAt.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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
