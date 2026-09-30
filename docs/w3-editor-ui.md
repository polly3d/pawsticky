# W3 · 编辑器 UI（详细记录）

> 提取自主计划 §6。完整任务卡见 `plan.md` §4。

**日期:** 2026-10-19 ~ 10-25（实际于 2026-09-30 完成大部分）
**状态:** ✅ 大体完成（W3-4 清单模式补做中）

---

## 任务拆解

| 子任务 | 内容 | 验收 |
|---|---|---|
| **W3-0 Core API 补全** ✅ | ①`toggleNote(id:)` 原子 per-note toggle ②`updateItem` 条目编辑 ③position-on-create MAX(position)+1 ④`CCPseudoRandomAlgorithm` 注释修 | 新 API 单测全绿 |
| **W3-1 w3.v1 schema + NoteStyle** ✅ | ALTER TABLE note ADD COLUMN style TEXT；`NoteStylePreset` enum（6 款预设色）| 迁移测试绿 |
| **W3-2 便签列表 + 一秒速记** ✅ | `NoteListView`；"+"一键创建（deferred creation）；滑删；空状态 | 创建→编辑器光标在正文 |
| **W3-3 编辑器 + 防抖落盘** ✅ | `NoteEditorView`；300ms 防抖；scenePhase 即时落盘；创建与编辑共用 sheet（`EditorMode` enum）| 杀进程零丢失 |
| **W3-4 清单模式** 📋 | 编辑器内 NoteItem 列表；划线完成；添加/勾选/删除/拖拽排序 | 勾选即划线；项目持久化 |
| **W3-5 到期提醒系统** ✅ | `NotificationScheduling` 协议；`ReminderManager`；due date picker；deep link（通知 tap → 打开便签）| 6 tests pass（FakeScheduler）|
| **W3-6 样式选择器** ✅ | `StylePickerView` 6 色圈；应用于编辑器背景 + 列表行；`ExportNote` DTO backward-compatible | 选色即时变色 |
| **W3-7 适配收口** ✅ | Accessibility labels；VoiceOver `.isSelected` trait | VoiceOver 走通 |

## 前置项消化（来自 W2 评审移交）

- ✅ W3-0①：`SharedStore.toggleNote(id:)` 原子对应物
- ✅ W3-0②：`updateItem`
- ✅ W3-0③：position-on-create 语义
- ✅ W3-0④：注释修
- ✅ W3-1：`style` 列 ALTER TABLE
- 📋 W3-3 移交：「读回库值为全等基准」— 编辑器 diff 逻辑遵守
- 📋 → W5：widget 进程写入不落历史

## 关键设计决策

### Deferred Creation（延迟创建）
用户点"+"不立即写库，sheet 弹出空编辑器。首次有实际内容时才 `createNote`。避免污染数据库（差评反面教训："requirement to name a note before it will save"）。

### EditorMode enum
```swift
enum EditorMode: Identifiable {
    case create
    case edit(UUID)
}
```
SwiftUI `.sheet(item: $editorMode)` 统一处理创建与编辑。

### Protocol-based Notification Scheduling
`NotificationScheduling` 协议 + `LiveNotificationScheduler`（真实 UNUserNotificationCenter）+ `FakeScheduler`（测试用）。`ReminderManager` 是无状态协调者，每次 save 后调用 `syncReminder(for:)`。

### Deep Link 链路
通知 tap → `UNUserNotificationCenterDelegate.didReceive` → `NotificationCenter.default.post(.pawItDeepLink)` → `NoteListView.onReceive` → `editorMode = .edit(noteID)`

## 新增文件

| 文件 | 用途 |
|---|---|
| `Core/Sources/Core/Models/NoteStyle.swift` | `NoteStylePreset` enum（6 色预设）|
| `Core/Sources/Core/Engine/NotificationScheduling.swift` | 协议 + Live/Fake 双实现 + ReminderManager |
| `Core/Tests/CoreTests/ReminderManagerTests.swift` | 6 个调度单测 |
| `PawIt/Features/Editor/StylePickerView.swift` | 色板选择器 UI |

## 测试统计

- **122 tests / 10 suites** 全绿
- 新增测试：SharedStoreTests ×5、NoteRepositoryTests ×7、ReminderManagerTests ×6、SchemaTests 更新 ×2
