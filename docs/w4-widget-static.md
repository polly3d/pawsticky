# W4 · Widget 家族（静态渲染）详细记录

> 完整任务卡见 `plan.md` §5。

**日期:** 2026-10-26 ~ 11-01
**状态:** ✅ 完成

---

## 任务拆解

| 子任务 | 内容 | 验收 |
|---|---|---|
| **W4-0 Widget 数据桥** | `WidgetDataProvider`：Widget 进程读取 App Group 数据库的统一入口；返回 `[WidgetNote]` 轻量视图模型（只含渲染所需字段，不暴露 GRDB 类型到 Widget target） | 单元测试绑定 SharedStore 读 |
| **W4-1 NoteWidgetFamily** | Widget 配置：支持 systemSmall / systemMedium / systemLarge；各尺寸独立渲染；时间线消费 TimelinePlanner（已有） | 三尺寸在模拟器可见 |
| **W4-2 锁屏 Widget 家族** | accessoryCircular / accessoryRectangular / accessoryInline；深色背景可读 | 锁屏三家族渲染正确 |
| **W4-3 Small Widget 渲染** | 便签卡片风格：背景色（NoteStylePreset）+ 正文摘要（2-3 行）+ 勾选状态划线 + 到期角标 | 视觉与编辑器风格一致 |
| **W4-4 Medium Widget 渲染** | 上半便签正文 + 下半清单项（最多 3-4 条，含勾选划线）| 清单项可见且对齐 |
| **W4-5 Large Widget 渲染** | 完整便签：正文 + 全部清单项（最多 6-8 条）+ 到期日 + 创建日期 | 长文本不截断不溢出 |
| **W4-6 锁屏渲染** | Circular：勾选状态图标；Rectangular：便签标题摘要 1-2 行；Inline：便签标题 | 深色背景对比度 OK |
| **W4-7 StandBy 支持** | systemSmall 在 StandBy 模式下正确渲染（高对比度） | StandBy 模式不破碎 |
| **W4-8 时间线集成** | getTimeline 读真实数据（不再是 PoC toggle state）；午夜翻转条目正确消费 TimelinePlanner | 跨午夜后 Widget 显示新一天数据 |

## 关键设计决策

### Widget 渲染读数据策略
- Widget 渲染时（`body` 计算）直接读 App Group SharedStore（W1 PoC B 已验证双进程安全）
- `getTimeline` 只负责时间线策略（何时刷新），不缓存数据
- 每次系统重绘 Widget 都从 DB 拿最新值（intent 交互后系统自动重绘 = 实时数据）

### 家族支持范围（iOS 17+）
- **主屏**：systemSmall / systemMedium / systemLarge
- **锁屏**：accessoryCircular / accessoryRectangular / accessoryInline
- **StandBy**：复用 systemSmall 渲染（iOS 17 自动适配）
- W5 再加交互（Button(intent:)），本周只做静态渲染

### 数据显示优先级
1. 第一条便签（position 排序首条）= Widget 默认展示
2. 有到期日的优先展示到期信息
3. 清单项按 position 排序展示前 N 条
