import SwiftUI
import Core

/// 便签列表——App 主界面（W3-2）。
///
/// 设计原则（来自竞品差评的反面教训）：
/// - "+" 一键创建，sheet 弹出编辑器，光标直达正文，无命名步骤
///   *"[2★ v5.0.0 2025-09-29] requirement to name a note before it will save"*
/// - 创建与编辑共用同一 sheet 编辑器
/// - 排序消费 `allNotes()`——与 Widget/store 同族同序
struct NoteListView: View {

    @State private var notes: [Note] = []
    /// 当前编辑器 sheet 的模式：nil = 未展示, .create = 新建, .edit(id) = 编辑已有便签
    @State private var editorMode: EditorMode?

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
        }
        .task { reloadNotes() }
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
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .refreshable { reloadNotes() }
    }

    // MARK: - Actions

    private func deleteNotes(at offsets: IndexSet) {
        guard let repository else { return }
        let toDelete = offsets.map { notes[$0] }
        Task {
            for note in toDelete {
                try? await repository.deleteNote(id: note.id)
            }
            reloadNotes()
        }
    }

    func reloadNotes() {
        guard let repository else { return }
        notes = (try? repository.allNotes()) ?? []
    }
}

// MARK: - EditorMode（sheet 展示的 Identifiable 包装）

/// 编辑器模式：创建 vs 编辑已有便签。遵循 Identifiable 以供 `.sheet(item:)` 使用。
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

// MARK: - 便签行

struct NoteRowView: View {
    let note: Note

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
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(
                            NoteEngine.isOverdue(note, now: .now) ? .red : .secondary
                        )
                }
                Spacer()
                Text(note.createdAt.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayTitle: String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }
        return String(trimmed.prefix(80))
    }
}
