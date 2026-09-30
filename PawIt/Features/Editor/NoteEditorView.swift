import SwiftUI
import Combine
import Core

/// 便签编辑器（W3-3）——sheet 呈现，创建与编辑共用。
///
/// **延迟创建 (deferred creation)**：
/// - Create 模式：sheet 打开时只有内存状态，数据库零写入。
///   用户首次输入后 300ms 防抖触发时才真正 createNote，之后切入 edit 模式。
///   若用户未输入任何内容就关闭 sheet → 什么都不发生（数据库零污染）。
/// - Edit 模式：从 DB 加载已有便签，300ms 防抖自动落盘。
///
/// 保存策略（D3 刷新策略的 App 内编辑路径）：
/// 1. 每次击键 → 300ms 防抖后自动落盘
/// 2. `scenePhase = .background` → 即时落盘
/// 3. Dismiss → 即时落盘
struct NoteEditorView: View {

    let mode: EditorMode
    let repository: NoteRepository?
    let onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var isDone: Bool = false
    @State private var items: [NoteItem] = []
    @State private var newItemText: String = ""

    /// 延迟创建追踪：create 模式下首次落盘后持有已创建的 noteID。
    @State private var persistedNoteID: UUID?
    @State private var isLoaded = false
    @FocusState private var isTextEditorFocused: Bool

    /// 防抖发布者：文本变更 → 300ms → 自动落盘
    @State private var saveSubject = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    /// 当前的有效 noteID（edit 模式下直接从 mode 取，create 模式下从 persistedNoteID 取）。
    private var effectiveNoteID: UUID? {
        switch mode {
        case .create: return persistedNoteID
        case .edit(let id): return id
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    noteTextEditor

                    if effectiveNoteID != nil {
                        checklistSection
                    }
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { loadIfNeeded(); setupDebounce() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { flushSave() }
        }
        .onDisappear { flushSave(); onDismiss() }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Note"
        case .edit: return isDone ? "Completed" : "Edit Note"
        }
    }

    // MARK: - Text Editor

    private var noteTextEditor: some View {
        TextEditor(text: $text)
            .font(.body)
            .focused($isTextEditorFocused)
            .frame(minHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start typing...")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 16)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { _, newValue in
                saveSubject.send(newValue)
            }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Checklist")
                .font(.headline)
                .padding(.top, 8)

            ForEach(items, id: \.id) { item in
                ChecklistItemRow(item: item) {
                    toggleItem(item)
                } onDelete: {
                    deleteItem(item)
                }
            }

            HStack {
                TextField("Add item...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .onSubmit { addItem() }
                Button(action: addItem) {
                    Image(systemName: "plus.circle")
                }
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        if effectiveNoteID != nil {
            ToolbarItem(placement: .primaryAction) {
                Button { toggleNote() } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? .green : .secondary)
                }
                .accessibilityLabel(isDone ? "Mark as incomplete" : "Mark as done")
            }
        }
    }

    // MARK: - Data Operations

    private func loadIfNeeded() {
        switch mode {
        case .create:
            isLoaded = true
            isTextEditorFocused = true
        case .edit(let id):
            guard let repository, let note = try? repository.note(id: id) else { return }
            text = note.text
            isDone = note.done
            items = (try? repository.noteItems(noteId: id)) ?? []
            persistedNoteID = id
            isLoaded = true
        }
    }

    private func setupDebounce() {
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [repository] newText in
                guard let repository else { return }
                Task { await debouncedSave(newText, repository: repository) }
            }
            .store(in: &cancellables)
    }

    /// 防抖触发的保存——处理 create 模式的延迟创建和 edit 模式的更新。
    @MainActor
    private func debouncedSave(_ newText: String, repository: NoteRepository) async {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let noteID = effectiveNoteID {
            // Edit 模式（或 create 模式下已创建）：更新已有便签
            if var note = try? repository.note(id: noteID) {
                note.text = newText
                try? await repository.updateNote(note)
            }
        } else if !trimmed.isEmpty {
            // Create 模式且首次有内容：延迟创建——此时才写入数据库
            if let note = try? await repository.createNote(text: newText) {
                persistedNoteID = note.id
            }
        }
    }

    /// 立即落盘（background/dismiss 时调用，跳过防抖）。
    private func flushSave() {
        guard let repository, isLoaded else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            if let noteID = effectiveNoteID {
                if var note = try? repository.note(id: noteID) {
                    note.text = text
                    try? await repository.updateNote(note)
                }
            } else if !trimmed.isEmpty {
                if let note = try? await repository.createNote(text: text) {
                    persistedNoteID = note.id
                }
            }
        }
    }

    private func toggleNote() {
        guard let repository, let noteID = effectiveNoteID else { return }
        Task {
            if let result = try? await repository.toggleNote(id: noteID) {
                isDone = result
            }
        }
    }

    private func toggleItem(_ item: NoteItem) {
        guard let repository, let noteID = effectiveNoteID else { return }
        Task {
            _ = try? await repository.toggleItem(noteId: noteID, itemId: item.id)
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repository, let noteID = effectiveNoteID else { return }
        Task {
            _ = try? await repository.addItem(to: noteID, text: trimmed)
            newItemText = ""
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }

    private func deleteItem(_ item: NoteItem) {
        guard let repository, let noteID = effectiveNoteID else { return }
        Task {
            try? await repository.deleteItem(noteId: noteID, itemId: item.id)
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }
}

// MARK: - Checklist Item Row

private struct ChecklistItemRow: View {
    let item: NoteItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Text(item.text)
                .strikethrough(NoteEngine.strikethrough(isDone: item.done))
                .foregroundStyle(item.done ? .secondary : .primary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
