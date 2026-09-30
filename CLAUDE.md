# PawIt 宠物便签 — 项目上下文

## 项目概述
PawIt（爪印便利贴）是一款 iOS 宠物主题便签 Widget App 的商业计划与调研项目。核心定位："由你的宠物帮你记住事情"——便签是骨，宠物是魂。

## 目录结构
- `宠物便签商业计划书.md` — 完整商业计划书（v1.1）
- `开发计划-PawIt-MVP.md` — 12 周开发实施计划（W1 已展开为细粒度步骤，W2-W12 为任务卡）
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
