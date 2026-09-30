import SwiftUI
import Combine
import Core

/// 便签编辑器（W3-3）——自动保存 + 零丢失的核心交互。
///
/// 保存策略（D3 刷新策略的 App 内编辑路径）：
/// 1. 每次击键 → 300ms 防抖后自动落盘（逐键安全）
/// 2. `scenePhase = .background` → 即时全量落盘 + `WidgetCenter.reloadTimelines`
/// 3. 用户返回列表（dismiss）→ 即时落盘
/// 演示脚本：输入中途强杀 App → 重开 → 零丢失（最多丢最后 300ms 的击键）
struct NoteEditorView: View {

    let noteID: UUID
    let repository: NoteRepository?
    let onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var isDone: Bool = false
    @State private var items: [NoteItem] = []
    @State private var newItemText: String = ""
    @State private var isLoaded = false

    /// 防抖发布者：文本变更 → 300ms → 自动落盘
    @State private var saveSubject = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                noteTextEditor
                if !items.isEmpty || isLoaded {
                    checklistSection
                }
            }
            .padding()
        }
        .navigationTitle(isDone ? "已完成" : "编辑便签")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { loadNote(); setupDebounce() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { flushSave() }
        }
        .onDisappear { flushSave(); onDismiss() }
    }

    // MARK: - 正文编辑器

    private var noteTextEditor: some View {
        TextEditor(text: $text)
            .font(.body)
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
                    Text("开始输入...")
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

    // MARK: - 清单区

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("清单")
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
                TextField("添加事项...", text: $newItemText)
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

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                toggleNote()
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? .green : .secondary)
            }
            .accessibilityLabel(isDone ? "标记未完成" : "标记完成")
        }
    }

    // MARK: - 数据操作

    private func loadNote() {
        guard let repository, let note = try? repository.note(id: noteID) else { return }
        text = note.text
        isDone = note.done
        items = (try? repository.noteItems(noteId: noteID)) ?? []
        isLoaded = true
    }

    private func setupDebounce() {
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [repository, noteID] newText in
                guard let repository else { return }
                Task {
                    if var note = try? repository.note(id: noteID) {
                        note.text = newText
                        try? await repository.updateNote(note)
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// 立即落盘（background/dismiss 时调用,跳过防抖）。
    private func flushSave() {
        guard let repository, isLoaded else { return }
        Task {
            if var note = try? repository.note(id: noteID) {
                note.text = text
                try? await repository.updateNote(note)
            }
        }
    }

    private func toggleNote() {
        guard let repository else { return }
        Task {
            if let result = try? await repository.toggleNote(id: noteID) {
                isDone = result
            }
        }
    }

    private func toggleItem(_ item: NoteItem) {
        guard let repository else { return }
        Task {
            _ = try? await repository.toggleItem(noteId: noteID, itemId: item.id)
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let repository else { return }
        Task {
            _ = try? await repository.addItem(to: noteID, text: trimmed)
            newItemText = ""
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }

    private func deleteItem(_ item: NoteItem) {
        guard let repository else { return }
        Task {
            try? await repository.deleteItem(noteId: noteID, itemId: item.id)
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }
}

// MARK: - 清单项行

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
