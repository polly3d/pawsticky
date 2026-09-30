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
                    Button { showPetSelection = true } label: {
                        Image(systemName: "pawprint.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Choose Pet")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editorMode = .create } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("New Note")
                }
            }
            .sheet(item: $editorMode) { mode in
                NoteEditorView(mode: mode, repository: repository) {
                    reloadNotes()
                }
            }
            .sheet(isPresented: $showPetSelection) {
                PetSelectionView { reloadNotes() }
            }
        }
        .task { reloadNotes() }
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
            ForEach(notes, id: \.id) { note in
                Button { editorMode = .edit(note.id) } label: {
                    NoteRowView(note: note)
                }
                .tint(.primary)
                .listRowBackground(presetFor(note).backgroundColor.opacity(0.25))
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .refreshable { reloadNotes() }
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
