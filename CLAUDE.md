# PawIt 宠物便签 — 项目上下文

## 项目概述
PawIt（爪印便利贴）是一款 iOS 宠物主题便签 Widget App 的商业计划与调研项目。核心定位："由你的宠物帮你记住事情"——便签是骨，宠物是魂。

**品牌名（2026-10-14 定稿）：PawSticky。** 用户可见字符串一律用 PawSticky；Bundle ID 前缀 `com.fitpetgo.pawsticky`，App Group `group.com.fitpetgo.pawsticky.shared`。代码内部名（target / module / 目录 `PawIt*`、Widget `kind`、`pawit.sqlite3` 等不透明标识）与历史文档沿用 PawIt，**不再改动**。依据见 `docs/launch-readiness.md` §7 / §10。

## 目录结构
- `docs/plan.md` — 12 周开发实施计划（精简鸟瞰图）
- `docs/business-plan.md` — 完整商业计划书（v1.1）
- `docs/w1-architecture.md` — W1 架构备忘录（D1-D6 裁决 / W2 前置项 / 工具链坑）
- `docs/w1-risk-elimination.md` — W1 详细任务与完成记录
- `docs/w2-data-layer.md` — W2 详细任务与完成记录
- `docs/w3-editor-ui.md` — W3 详细任务与完成记录
- `docs/launch-readiness.md` — v1.0 上线就绪审计（P0/P1/P2 差距清单 / ASC 提审清单 / 命名评估 / 待决策项）
- `docs/launch-art-prompts.md` — 上线美术资源清单与 gpt-image-2.5 提示词包（图标 / 举牌 / front / 装扮 / 营销）
- `docs/assets/launch-audit/` — 上线审计的证据截图
- `art/` — 美术资产与生成管线（风格已冻结 B 扁平矢量+描边，见 `art/style-pack/style-notes.md`）
- `research/` — 一手调研数据（iTunes API 抓取，2026-09-29）
  - `lookup-*.json` — 竞品元数据（iTunes Lookup API）
  - `reviews-*-p[1-4].json` — 竞品用户评论原始 JSON（iTunes RSS API）
  - `reviews-*-highs.txt` — 好评摘要（4-5★）
  - `reviews-*-lows.txt` — 差评摘要（1-3★）
  - `search-*.json` — 赛道竞品搜索结果（iTunes Search API）

## 竞品 ID 对照
- `1533254320` = Sticky Widgets（1881 Digital, LLC）— 品类第一
- `1538284842` = Stickies（Luca Meghnagi）— 弃更样本

## 数据统计基准
- Sticky Widgets: 150 条近期评论，1★ 76 条（50.7%），1-2★ 合计 62.0%
- Stickies: 43 条近期评论，1★ 28 条（65.1%），1-2★ 合计 74.4%
- 两款合计: 193 条评论，其中 141 条中差评（1-3★）

## 编辑规范
- 商业计划书使用中文撰写，数据引用保留英文原文
- 所有数据声明需标注 `research/` 目录下的来源文件
- 评论原声引用格式：`"引文" — [★数 版本 日期] 标题`

## 代码规范
- **UI 文案语言**：所有用户可见的字符串（按钮文本、标签、占位文字、错误提示等）一律使用**英语**。v1.0 目标市场以英语为主（EN + zh-Hans），中文翻译通过 Localizable.strings 提供，不在代码中硬编码中文。
- **代码注释语言**：Swift 代码注释和文档注释使用中文（与商业计划书、开发计划保持一致）。
- **i18n 就绪**：SwiftUI 的 `Text("...")` 天然支持 `LocalizedStringKey`，使用英文字面量即可在将来通过 `.strings` 文件扩展多语言，无需额外包装。
- **Commit 消息**：英语，格式 `feat/fix/test/refactor/docs: <内容>`。
