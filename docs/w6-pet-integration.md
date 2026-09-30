# W6 · 宠物层集成（详细记录）

> 完整任务卡见 `plan.md` §5。

**日期:** 2026-11-09 ~ 11-15
**状态:** ✅ 完成（代码层；真实 PNG 资产待 art pipeline 产出）

---

## 任务拆解

| 子任务 | 内容 | 验收 |
|---|---|---|
| **W6-0 PetAsset 枚举** | `PetAsset`：species→资产名映射；各宠物的姿势枚举（holding/sitting/happy）；资产目录 placeholder | 编译通过 |
| **W6-1 PetNoteRenderer** | 布局引擎：宠物图 + 便签卡片的组合渲染；适配 systemSmall/Medium/Large 三尺寸；状态机（姿势×心情×尺寸） | 单测绿 |
| **W6-2 Widget 宠物集成** | W4/W5 的 Widget 渲染器接入 PetNoteRenderer；选中宠物从 DB 读取 | Widget 显示宠物举牌 |
| **W6-3 App 宠物选择** | 宠物选择界面（6 宠物网格）；选择后持久化 isSelected | 选择即生效 |
| **W6-4 喂食庆祝动画** | SwiftUI 原生动画：完成任务 → 宠物喂食反馈（心形粒子/弹跳）| SE 不掉帧 |
| **W6-5 资产占位** | 6 宠物的 SF Symbol 占位图（真实 PNG 资产需手动生成管线产出，本周用占位） | 占位可渲染 |

## 关键设计决策

### 资产策略（现实约束）
真实 PNG 资产需要通过 gpt-image-2.5 管线手动生成（每只宠物 8-10 姿势 × @1x/2x/3x），这不是代码能自动完成的。W6 的代码层面：
1. 定义完整的资产名枚举和布局引擎
2. 使用 SF Symbols 作为开发期占位
3. 真实资产通过 Asset Catalog 按命名规范放入后自动生效

### PetNoteRenderer 状态机
- 输入：(species, pose, mood, widgetFamily)
- 输出：组合布局（宠物位置、大小、便签卡片偏移）
- 纯值函数，可单测
