# W2 · 数据层 + 便签引擎（详细记录）

> 提取自主计划 §6。完整任务卡见 `plan.md` §4。

**日期:** 2026-10-12 ~ 10-18（实际提前于 2026-09-30 完成）
**状态:** ✅ 收官

---

## 任务拆解

| 子任务 | 内容 | 验收 |
|---|---|---|
| **W2-1 可靠性四件套** ✅ | ①进程级单池 ②迁移竞态 retry-once ③初始化失败不缓存 nil ④文件保护 ⑤首条排序 id 决胜 | `5c401cc`（29 测试） |
| **W2-2 w2.v1 schema + 模型** ✅ | Note（dueDate/position）、NoteItem、PetProfile、GrowthState；DatabaseMigrator 扩展 | `4ad2365`（43 测试） |
| **W2-3 NoteEngine** ✅ | 勾选/划线/排序/午夜翻转/到期语义；消费 TimelinePlanner 日界 | `15394c1`（61 测试） |
| **W2-4 NoteRepository + HistoryLog + 导出** ✅ | CRUD、7 天回滚日志、JSON 导出/导入（可选口令加密）| `aeca420`+`2f19e0f`（107 测试，覆盖率 ≈95.8%）|
| **W2-5 角色卡补齐** ✅ | 6/6 齐备（灰白猫/柴犬/兔/仓鼠 + W1 猫/柯基） | 用户眼验通过 |

## 评审移交登记

**→ W3（来自 W2-3 质量评审）：**
- `SharedStore.toggleNote(id:)` 原子对应物 → ✅ W3-0 消化
- CI 固化 xcodebuild DoD 路径 → 📋 待定

**→ W3（来自 W2-4 质量评审）：**
- ①`updateItem`（条目文本/position 编辑）→ ✅ W3-0 消化
- ②position-on-create 语义（MAX+1）→ ✅ W3-0 消化
- ③「读回库值为全等基准」→ 📋 编辑器 diff 逻辑遵守
- ④widget 进程写入不落历史 → 📋 W5 消化

**→ W2-3 规格评审（来自 W2-2 质量评审）：**
- ①`firstNote`/`toggleFirstItem` 排序补 `position` 列
- ②dueDate NULL 排序显式决策
- ③午夜翻转语义决策（done 持久保留，日界只影响分组与喂养结算）
- ④补测试：pet→growth 级联、假 noteId FK 拒绝
- ⑤Package.swift 注释：`swift test` macOS 宿主编译限制

**→ W2-4（来自 W2-1 遗留）：**
- 缓存失败加 os_log 诊断
- WAL 边车重建后保护重设 hook

**→ w3.v1 设计时：**
- style 列 ALTER TABLE → ✅ W3-1 消化

## 收官总结

> **W2 收官（2026-09-30）**：5/5 子任务完成。**107 测试全绿零警告**；覆盖率 ≈95.8%。三层「零丢数据」机制齐备：WAL 双进程存储（W1）→ 每变更同事务历史快照（W2-4）→ 加密导出换机（W2-4）。Commit 链：5c401cc → 4ad2365 → 15394c1 → aeca420 → 2f19e0f。
