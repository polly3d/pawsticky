import SwiftUI
import Combine
import Core

/// 便签编辑器（W3-3/5/6/7）——sheet 呈现，创建与编辑共用。
///
/// **延迟创建 (deferred creation)**：
/// - Create 模式：sheet 打开时只有内存状态，数据库零写入。
///   用户首次输入后 300ms 防抖触发时才真正 createNote，之后切入 edit 模式。
///   若用户未输入任何内容就关闭 sheet → 什么都不发生（数据库零污染）。
/// - Edit 模式：从 DB 加载已有便签，300ms 防抖自动落盘。
///
/// **保存策略**（D3 刷新策略的 App 内编辑路径）：
/// 1. 每次击键 → 300ms 防抖后自动落盘
/// 2. `scenePhase = .background` → 即时落盘
/// 3. Dismiss → 即时落盘
///
/// **提醒调度**（W3-5）：每次保存后调用 `ReminderManager.syncReminder` 自动排程/取消。
struct NoteEditorView: View {

    let mode: EditorMode
    let repository: NoteRepository?
    let onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    // 便签字段
    @State private var text: String = ""
    @State private var isDone: Bool = false
    @State private var dueDate: Date?
    @State private var style: String?
    @State private var items: [NoteItem] = []
    @State private var newItemText: String = ""

    // UI 状态
    @State private var showDueDatePicker = false
    @State private var showStylePicker = false
    @State private var persistedNoteID: UUID?
    @State private var isLoaded = false
    @FocusState private var isTextEditorFocused: Bool

    // 防抖
    @State private var saveSubject = PassthroughSubject<Void, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    private let reminderManager = ReminderManager()

    /// 当前的有效 noteID（edit 模式直接取，create 模式从 persistedNoteID 取）。
    private var effectiveNoteID: UUID? {
        switch mode {
        case .create: return persistedNoteID
        case .edit(let id): return id
        }
    }

    /// 当前预设色（nil 回退 classicYellow——解析单一入口 `NoteStylePreset.resolve`）。
    private var currentPreset: NoteStylePreset {
        NoteStylePreset.resolve(style)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    noteTextEditor

                    if showDueDatePicker || dueDate != nil {
                        dueDateSection
                    }

                    if showStylePicker {
                        StylePickerView(selectedStyle: $style)
                            .onChange(of: style) { _, _ in triggerSave() }
                    }

                    if effectiveNoteID != nil {
                        checklistSection
                    }
                }
                .padding()
            }
            .background(currentPreset.backgroundColor.opacity(0.2).ignoresSafeArea()
                .overlay(AppTheme.background.opacity(0.4).ignoresSafeArea())
            )
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
        .onDisappear {
            // 先取消防抖订阅再冲刷——否则 dismiss 后 300ms 内排队的保存事件
            // 仍会触发一次冗余写库（多一条历史 + 一次提醒同步）。
            cancellables.removeAll()
            flushSave()
            onDismiss()
        }
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
            .font(AppTheme.body)
            .foregroundStyle(currentPreset.textColor)
            .focused($isTextEditorFocused)
            .frame(minHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(currentPreset.backgroundColor)
                    .shadow(
                        color: AppTheme.cardShadow.color,
                        radius: AppTheme.cardShadow.radius,
                        y: AppTheme.cardShadow.y
                    )
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start typing...")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(currentPreset.textColor.opacity(0.35))
                        .padding(.leading, 18)
                        .padding(.top, 22)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { _, _ in triggerSave() }
            .accessibilityLabel("Note text")
    }

    // MARK: - Due Date（W3-5）

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reminder", systemImage: "bell")
                    .font(AppTheme.cardTitle)
                Spacer()
                if dueDate != nil {
                    Button("Clear") {
                        withAnimation { dueDate = nil; showDueDatePicker = false }
                        triggerSave()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }

            DatePicker(
                "Due date",
                selection: Binding(
                    get: { dueDate ?? Date.now.addingTimeInterval(3600) },
                    set: { dueDate = $0; triggerSave() }
                ),
                in: Date.now...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }

    // MARK: - Checklist（W3-4）

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Checklist")
                    .font(AppTheme.cardTitle)
                Spacer()
                if !items.isEmpty {
                    Text("\(items.doneCount)/\(items.count)")
                        .font(AppTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(.top, 8)

            if items.isEmpty {
                Text("Add your first item")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ChecklistItemRow(item: item, preset: currentPreset) {
                        toggleItem(item)
                    } onDelete: {
                        deleteItem(item)
                    }
                    .draggable(item.id.uuidString) {
                        ChecklistItemRow(item: item, preset: currentPreset, onToggle: {}, onDelete: {})
                            .frame(width: 300)
                            .opacity(0.8)
                    }
                    .dropDestination(for: String.self) { droppedIDs, _ in
                        guard let droppedID = droppedIDs.first,
                              let fromIndex = items.firstIndex(where: { $0.id.uuidString == droppedID }),
                              fromIndex != index else { return false }
                        moveItem(from: fromIndex, to: index)
                        return true
                    }
                }
            }

            HStack {
                TextField("Add item...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .onSubmit { addItem() }
                    .accessibilityLabel("New checklist item")
                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add checklist item")
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
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation { showStylePicker.toggle() }
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundStyle(showStylePicker ? Color.accentColor : .secondary)
            }
            .accessibilityLabel("Color picker")

            Button {
                Task {
                    await reminderManager.ensureAuthorization()
                    withAnimation { showDueDatePicker.toggle() }
                }
            } label: {
                Image(systemName: dueDate != nil ? "bell.fill" : "bell")
                    .foregroundStyle(dueDate != nil ? .orange : .secondary)
            }
            .accessibilityLabel(dueDate != nil ? "Edit reminder" : "Set reminder")

            if effectiveNoteID != nil {
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
            dueDate = note.dueDate
            style = note.style
            items = (try? repository.noteItems(noteId: id)) ?? []
            persistedNoteID = id
            isLoaded = true
            showDueDatePicker = note.dueDate != nil
        }
    }

    private func triggerSave() {
        saveSubject.send()
    }

    private func setupDebounce() {
        saveSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [repository] in
                guard let repository else { return }
                Task { @MainActor in await debouncedSave(repository: repository) }
            }
            .store(in: &cancellables)
    }

    @MainActor
    private func debouncedSave(repository: NoteRepository) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let noteID = effectiveNoteID {
            if var note = try? repository.note(id: noteID) {
                note.text = text
                note.dueDate = dueDate
                note.style = style
                // 编辑会话合并（P2）：连续防抖落盘不逐条落前像，回滚回到会话起点。
                try? await repository.updateNote(note, history: .coalesce())
                await reminderManager.syncReminder(for: note)
            }
        } else if !trimmed.isEmpty {
            // 一步事务带 style 创建——此前 create + update 两步两事务,
            // 崩溃窗口会丢 style,且第二步历史前像无语义价值。
            if let note = try? await repository.createNote(text: text, dueDate: dueDate, style: style) {
                persistedNoteID = note.id
                await reminderManager.syncReminder(for: note)
            }
        }
    }

    private func flushSave() {
        guard let repository, isLoaded else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            if let noteID = effectiveNoteID {
                if var note = try? repository.note(id: noteID) {
                    note.text = text
                    note.dueDate = dueDate
                    note.style = style
                    try? await repository.updateNote(note, history: .coalesce())
                    await reminderManager.syncReminder(for: note)
                }
            } else if !trimmed.isEmpty {
                // 与 debouncedSave 同一创建路径——快速 dismiss 不再丢 style（P0-2）。
                if let note = try? await repository.createNote(text: text, dueDate: dueDate, style: style) {
                    persistedNoteID = note.id
                    await reminderManager.syncReminder(for: note)
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
            // position-on-create 已在 repository.addItem 落实（MAX+1）——
            // 此前这里算好了 maxPos+1 却调用不接受 position 的 API，是死代码。
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

    /// 拖拽排序：将 fromIndex 处的项目移动到 toIndex 处，并更新所有受影响项的 position。
    private func moveItem(from source: Int, to destination: Int) {
        guard let repository, let noteID = effectiveNoteID else { return }

        var reordered = items
        let moving = reordered.remove(at: source)
        let insertAt = destination > source ? destination - 1 : destination
        reordered.insert(moving, at: min(insertAt, reordered.count))

        // 乐观更新 UI
        items = reordered

        // 持久化新 position
        Task {
            for (index, var item) in reordered.enumerated() where item.position != index {
                item.position = index
                try? await repository.updateItem(item)
            }
            // 重新从 DB 加载确保一致
            items = (try? repository.noteItems(noteId: noteID)) ?? []
        }
    }
}

// MARK: - Checklist Item Row

private struct ChecklistItemRow: View {
    let item: NoteItem
    let preset: NoteStylePreset
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
            .accessibilityLabel(item.done ? "Completed: \(item.text)" : "Incomplete: \(item.text)")

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
            .accessibilityLabel("Delete \(item.text)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
