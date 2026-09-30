# W5 · 交互式 Widget + App Intents（详细记录）

> 完整任务卡见 `plan.md` §5。

**日期:** 2026-11-02 ~ 11-08
**状态:** 🚧 进行中

---

## 任务拆解

| 子任务 | 内容 | 验收 |
|---|---|---|
| **W5-0 ToggleItemIntent 升级** | 从 toggleFirstItem → toggle 当前展示的 note（by ID）；走 SharedStore 直写（widget 进程不落历史——W2-4 移交项④的既定决策） | toggle 单测绿 |
| **W5-1 CycleNoteIntent** | Widget 内翻页：在便签间循环切换；持久化当前 index 到 UserDefaults（App Group） | 翻页后 Widget 显示下一条 |
| **W5-2 AppendNoteIntent** | Siri + 快捷指令速记："Hey Siri, add Buy cat food to PawIt"；创建新便签 | Siri 端到端创建 |
| **W5-3 Widget 交互集成** | W4 渲染器加 Button(intent:)；勾选动画（划线过渡）；翻页按钮 | Widget 内可点击操作 |
| **W5-4 App 前台 reload** | App 前台变更后 `WidgetCenter.reloadTimelines`（已部分实现于 scenePhase） | App 编辑→回桌面→Widget ≤2s 更新 |
| **W5-5 Intent 单测** | FakeStore mock 的 intent perform 测试；并发安全 | 测试全绿 |

## W2 评审移交消化
- 📋 widget 进程写入不落历史 → W5-0 直写 SharedStore（不走 NoteRepository），是既定设计
