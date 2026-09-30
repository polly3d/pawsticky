# PawIt MVP 12 周开发实施计划

> **修订记录**：v1.2（2026-09-30）文档拆分至 `docs/`；v1.1 技术栈复审；v1.0 经两轮独立评审通过。

> **For agentic workers：** 本计划按周组织。每周开工前在 `docs/wN-*.md` 展开细粒度计划再执行。执行时配合 TDD：先写失败测试，再写实现。各周详细实施记录见对应 `docs/wN-*.md` 文件。

**Goal:** 交付商业计划书 §4.2 定义的 v1.0 MVP——便签内核做到品类最佳 + 宠物情感层 + 轻养成 + Watch Smart Stack，2026-12 圣诞软上线。

**Architecture:** 本地优先——iPhone App 与 iOS Widget 扩展共享 App Group 数据容器；**watchOS 端持有独立的只读镜像存储，由 WatchConnectivity 从手机推送最新快照**（App Group 容器不跨设备，见决定 D6）。交互式 Widget 通过 App Intents 在 Widget 内完成勾选/翻页（绕开刷新预算），宠物资产由 gpt-image-2.5 管线离线产出打包入 App，用户侧 AI 形象走 Cloudflare Worker 轻代理。**零第三方 SDK，隐私标签目标「Data Not Collected」**。

**Tech Stack:** Swift 6 / SwiftUI / **GRDB（SQLite，WAL 模式，App Group 双进程）** / WidgetKit + App Intents / watchOS WidgetKit / StoreKit 2（原生） / **Swift Testing** / **XcodeGen** / xcodebuild + TestFlight。

**依据:** 功能范围 = `docs/business-plan.md` §4.2/§4.5/§4.6；技术栈复审依据见本文 §9。

---

## 0. 执行约定

- **Commit 纪律**：小步提交，消息格式 `feat/fix/test/refactor: <内容>`；每周五打 tag `week-N`。
- **TDD 约定**：数据层、便签引擎、养成逻辑必须先写失败测试；Widget/UI 用手测协议（§7）。
- **工程生成纪律**：`project.yml`（XcodeGen）定义，**禁止手改 `.xcodeproj`**。
- **每周五复盘**（30 分钟）：未完成项要么砍要么排入下周首位——**不静默滚动**。
- **范围变更规则**：新增需求必须同时砍等量需求。
- **设备闸门**：TestFlight 前必须通过 §7 QA 矩阵最低配置。

## 1. 架构总览与文件结构

### 1.1 Target 布局

```
PawIt.xcodeproj
├── PawIt/                      # iOS 主 App
│   ├── App/PawItApp.swift
│   ├── Features/
│   │   ├── Editor/             # 便签编辑器
│   │   ├── Pets/               # 宠物选择/装扮
│   │   ├── Growth/             # 轻养成仪表盘
│   │   ├── CaptureAI/          # AI 形象（v1.0 beta）
│   │   ├── Paywall/            # StoreKit 2 付费墙
│   │   └── Settings/           # 数据导出
├── PawItWidget/                # WidgetKit 扩展（iOS）
├── PawItWatch/                 # watchOS App
├── Core/                       # ⭐ 三 target 共享的纯逻辑层
│   ├── Models/
│   ├── Store/
│   ├── Engine/
│   ├── Intents/
│   └── Paywall/
└── PawItTests/                 # Swift Testing
```

### 1.2 关键数据流

```
Widget 勾选 → ToggleItemIntent → Core/Store 写 App Group → 系统自动重渲染
App 编辑   → 300ms 防抖落盘 → scenePhase=.background 即时全量落盘 + WidgetCenter.reloadTimelines
```

## 2. 六个技术决定

| # | 决定 | 理由 |
|---|---|---|
| D1 | **最低 iOS 17.0** | 交互式 Widget 护城河 |
| D2 | **GRDB（SQLite）App Group WAL** | 双进程、零丢失甜区（§9 依据）|
| D3 | **刷新由用户动作驱动** | 不依赖系统刷新预算 |
| D4 | **StoreKit 2 原生** | 零第三方 → 「Data Not Collected」|
| D5 | **Cloudflare Worker 代理 AI** | 不嵌 key、免费额度充足 |
| D6 | **Watch = WatchConnectivity 镜像** | App Group 不跨设备 |

## 3. v1.0 不做清单

- iCloud 同步（v1.1）| 情侣共养（v1.2）| 宠物世界（v2.0）
- 完整 watchOS 语音速记（v1.1）| 8 语言本地化（v1.0 仅 EN + zh-Hans）
- Android | Lottie 动画 | 预注册账号体系（永不）

## 4. 12 周排期总表

| 周 | 主题 | 状态 | 详细记录 |
|---|---|---|---|
| **W1** | 风险消除 + PoC | ✅ | [`docs/w1-risk-elimination.md`](w1-risk-elimination.md) |
| **W2** | 数据层 + 便签引擎 | ✅ | [`docs/w2-data-layer.md`](w2-data-layer.md) |
| **W3** | 编辑器 UI | ✅ | [`docs/w3-editor-ui.md`](w3-editor-ui.md) |
| **W4** | Widget 家族（静态渲染）| ✅ | [`docs/w4-widget-static.md`](w4-widget-static.md) |
| **W5** | 交互式 Widget + App Intents | 📋 | — |
| **W6** | 宠物层集成 | 📋 | — |
| **W7** | 轻养成 + 分享卡片 | 📋 | — |
| **W8** | 商业化 | 📋 | — |
| **W9** | AI 形象 beta + 轻后端 | 📋 | — |
| **W10** | watchOS | 📋 | — |
| **W11** | QA 矩阵 + TestFlight 公测 | 📋 | — |
| **W12** | 修复 + 软上线 | 📋 | — |

**降级阶梯**：W9 AI → W10 Watch → 分享卡片降级截图。**永不可砍**：W1-W5。

**并行轨**：App 图标（截止 W10 末）| TikTok build-in-public（W6 起）| TestFlight 招募（W9 启动）。

## 5. W4-W12 任务卡

### W4 · Widget 家族（静态渲染）
**核心任务:** `NoteWidgetFamily` 覆盖 systemSmall/Medium/Large + accessoryCircular/Rectangular/Inline（锁屏）+ StandBy；时间线预生成（午夜翻转）。
**DoD:** 全家族在 SE / 16 Pro Max / iPad 10th 截图无裁切遮挡；锁屏深色可读；跨午夜真机翻转。
**测试:** 手测协议 §7-W；渲染快照存 `qa/screenshots/`。

### W5 · 交互式 Widget + App Intents
**核心任务:** `ToggleItemIntent`/`CycleNoteIntent`/`AppendNoteIntent` 接入真实 Repository；Widget 内勾选动画。
**DoD:** 真机勾选 <100ms；强杀 App 后 intent 仍工作；Siri 速记端到端；**连续 50 次勾选零丢失**。
**测试:** Intent 单测；手测协议 §7-I。

### W6 · 宠物层集成
**核心任务:** `PetNoteRenderer`（姿势×心情×尺寸状态机）；6 宠物×8-10 姿势 + 12 件装扮入包；喂食动画。
**DoD:** 资产增量 <15MB；每宠物 3 种 Widget 尺寸无破碎；SE 不掉帧。
**测试:** 布局状态机单测；资产完整性脚本。

### W7 · 轻养成 + 分享卡片
**核心任务:** `GrowthEngine`（完成→喂食→连击→装扮解锁 12 件；**断签不惩罚**）；分享卡片导出（IG Story 1080×1920）。
**DoD:** 养成单测全绿；卡片导出端到端；「关闭养成」开关可用。
**测试:** `GrowthEngineTests`。

### W8 · 商业化
**核心任务:** StoreKit 2 三档（$1.49/月、$5.99/年 7 天试用、$14.99 买断）；`Gate` 门控；**弹窗频控 ≤1/周**。
**DoD:** 沙盒三档购买/恢复/退款全通；免费档走查。
**测试:** `GateTests`（门控矩阵×频控）。

### W9 · AI 形象 beta + 轻后端
**核心任务:** Cloudflare Worker 单端点；上传→生成→设为我的宠物；**feature flag 可关闭**。
**DoD:** 全链路端到端；限流生效；隐私标签"照片不存储"。
**测试:** Worker 单测；端到端手测。

### W10 · watchOS
**核心任务:** D0 WatchConnectivity PoC → Smart Stack widget + 复杂功能。
**DoD:** 同步 PoC 通过；Watch 真机出片；44mm/41mm 校验。**周三降级检查点**。
**测试:** 手测 §7-AW。

### W11 · QA 矩阵 + TestFlight 公测
**核心任务:** §7 全量执行；外测 200 人；ASO 资产。
**DoD:** 崩溃率 <0.1%；SE/11 全通过。

### W12 · 修复 + 软上线
**核心任务:** 公测修复；分区上线（NZ→CA→US）；监控就位。
**DoD:** 美区可见；首发周评分 ≥4.5。

---

## 6. QA 矩阵与手测协议

**设备最低矩阵:** iPhone SE 2nd/3rd · iPhone 11 · iPhone 16 Pro · iPad 10th · Watch SE 2 / S9

| 协议 | 场景 | 通过标准 |
|---|---|---|
| P1 速记 | 点 Widget→输入→杀进程→重开 | 零丢失，无需命名 |
| P2 换机 | 导出→新设备导入 | 数据完整 |
| W 刷新 | App 内改字→回桌面 | ≤2s 更新 |
| I 交互 | 强杀 App 后 Widget 勾选 | 正常，<100ms |
| W-午夜 | 跨 00:00 放置 Widget | 翻转正确 |
| AW 同步 | 手机改 10 次 | Watch ≤10s 收敛 |
| DW 深色 | 深色模式 + 锁屏 | 全元素可读 |

## 7. 里程碑闸门

| 闸门 | 时间 | 通过线 |
|---|---|---|
| G1 架构 | W1 末 | 3 个 PoC 证实 ✅ |
| G2 可靠 | W5 末 | 50 连击零丢失；<100ms |
| G3 完整 | W8 末 | 沙盒购买全通；免费档合格 |
| G4 发布 | W11 末 | QA 全绿；崩溃率 <0.1% |
| G5 线上 | +30 天 | 评分 ≥4.5 |

## 8. 技术栈复审依据（2026-09-30，v1.1）

- **GRDB > SwiftData**：Fatbobman、Michael Tsai、Apple Forums 活跃问题、HackerNoon 选型指南——查询极简 + 双进程 + 零丢失 → GRDB 甜区。
- **Swift Testing**：Xcode 26 默认；XCUITest 仅 UI 冒烟。
- **XcodeGen**：纯文本 YAML 对 LLM 可读可 diff。
- **min iOS 17**：TelemetryDeck 2026 数据 17+ ≈90%。
- **StoreKit 2**：「Data Not Collected」硬卖点。

---

*每周开工：在对应 `docs/wN-*.md` 展开细粒度计划。*
