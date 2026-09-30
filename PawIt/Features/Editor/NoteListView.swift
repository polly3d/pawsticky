import SwiftUI
import Core

/// 便签列表——App 主界面（W3-2）。
///
/// 设计原则（来自竞品差评的反面教训）：
/// - 一键创建，光标直达正文，无命名步骤
///   *"[2★ v5.0.0 2025-09-29] requirement to name a note before it will save"*
/// - 列表即时刷新，滑删可撤回
/// - 排序消费 `allNotes()`——与 Widget/store 同族同序
struct NoteListView: View {

    @State private var notes: [Note] = []
    @State private var navigateToNoteID: UUID?

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
                    Button(action: createNote) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("新建便签")
                }
            }
            .navigationDestination(for: UUID.self) { noteID in
                NoteEditorView(noteID: noteID, repository: repository) {
                    reloadNotes()
                }
            }
        }
        .task { reloadNotes() }
        .onChange(of: navigateToNoteID) { _, newValue in
            // 响应 deep link 或创建后导航
        }
    }

    // MARK: - 子视图

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有便签", systemImage: "note.text")
        } description: {
            Text("点右上角 + 开始记录")
        } actions: {
            Button("创建第一条便签", action: createNote)
                .buttonStyle(.borderedProminent)
        }
    }

    private var noteList: some View {
        List {
            ForEach(notes, id: \.id) { note in
                NavigationLink(value: note.id) {
                    NoteRowView(note: note)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
        .refreshable { reloadNotes() }
    }

    // MARK: - 操作

    private func createNote() {
        guard let repository else { return }
        Task {
            if let note = try? await repository.createNote(text: "") {
                reloadNotes()
                navigateToNoteID = note.id
            }
        }
    }

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
        if trimmed.isEmpty { return "新便签" }
        return String(trimmed.prefix(80))
    }
}
