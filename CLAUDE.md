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
- **`docs/launch-todo.md` — v1.0 上线 TODO：唯一回答"现在该做什么、做到哪了"的文档（A 拍板 / B 真机 / C 代码 / D 站点+ASC / E 出包；已完成项折叠在文末）。状态一律以它为准。**
- `docs/launch-readiness.md` — v1.0 上线就绪审计快照（P0/P1/P2 差距清单 / ASC 提审清单 / 命名评估 / 决策记录）；只保留"为什么"，不再记进度
- `docs/launch-art-prompts.md` — 美术提示词包；**v1.0 不需要生成新图**（零生成方案见 todo），仅供以后补图
- `docs/pawsticky-privacy-policy.md` — 可直接发布的 App 隐私政策英文稿（fitpetgo.com 现有页面只覆盖网站，不能给 App 用；任何 SDK / 网络请求 / 新权限变化都要同步改它和 ASC 隐私问卷）
- `docs/simulator-playbook.md` — 模拟器验证手册：哪些事模拟器能证明 / 证明不了、种数据 / 临时启动参数补丁 / 配对模拟器 / Live Activity 日志 / 离屏渲染的做法与命令、动用户正在用的模拟器时的规矩；**要在模拟器里验东西之前先读它**
- `docs/assets/launch-audit/` — 上线审计的证据截图（含修复后的对比图 08 / 09、零生成复用对比 10、图标三选一 11、新美术在 App 内的截图 12 / 13、设置页 14、撤销与备份 15 / 16、小组件点按直达 17、Watch 同步修复前后对比 18、pin 图标修复前后对比 19、Watch 智能叠放卡片修复前后对比 20）
- `Config/` — 构建配置：`Base.xcconfig`（由 `project.yml` 引用）+ 本地签名模板 `Signing.local.xcconfig.example`
- `scripts/preflight.sh` — 上线验收脚本（Bundle ID / App Group / 品牌名 / 版本号 / 隐私清单 / 外观 / 合规键 / 设备族 / 深链 scheme / Live Activity 小呈现的图片尺寸）
- `scripts/run-tests.sh` — 全量测试封装：绕开“测试跑完 xcodebuild 却挂住”，只按自己的 PID 回收，末尾列出本次编译的警告；退出码 0 全绿 / 1 失败 / 2 无法判定
- `art/` — 美术资产与生成管线（风格已冻结 B 扁平矢量+描边，见 `art/style-pack/style-notes.md`）
  - `art/scripts/gen-images.sh` — 文生图（**无参考图输入**，禁止用它批量重抽宠物，会风格漂移）
  - `art/scripts/extract-from-sheets.sh` — **零生成**：从已有角色卡抠出完整正面图 + 胸像并描边（v1.0 宠物图的来源）
  - `art/scripts/export-pet-imagesets.sh` — 把抠出的图导出为 4 个 catalog 的 `pet-<sp>-front`（+ `pet-cat-full`），并给 Widget catalog 导出 Live Activity 小呈现专用的 `pet-<sp>-badge`（48/96/144px，**≤144px 是硬上限**，见代码规范“Live Activity 的图片尺寸”）
  - `art/scripts/make-app-icon.sh` — 用 `B_cat-sitting` 合成天蓝底 App 图标并写入 iOS / watchOS 的 AppIcon
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
- **站内跳转（深链）**：scheme 是 `pawsticky://`（`new` / `note/<UUID>`）。契约只在 Core 的 `DeepLink`（构造 + 严格白名单解析，别在别处手拼 URL）；注册在 `project.yml` 的 `CFBundleURLTypes`（改 scheme 两处同步，`PawItTests` 与 `scripts/preflight.sh` 会核对）；App 端 `onOpenURL` → `DeepLinkRouter`（挂起，供冷启动）→ `NoteListView` 取走。新增链接类型只许“打开某个页面”，不许携带会改数据的动作——scheme 注册后网页和别的 App 都能触发它。
- **Watch 同步（WatchConnectivity）**：iPhone 端 `PhoneSessionManager` 负责推（激活 / 回前台 / 便签变更 / `sessionWatchStateDidChange`）与答（`didReceiveMessage` 回当前快照）；手表端 `WatchSessionManager` 负责拉（激活 / 回前台 / 连通性恢复时 `requestSnapshot()`）。手表界面**只读** Core 的 `WatchSnapshotStore`（`@Observable`；新 `syncDate` 优先、同时间戳幂等），**不要**在视图里一次性读 UserDefaults——数据后到就永远不重绘，这是 2.1(a) 被拒的原因之一。“要快照”请求的契约只在 `WatchPayload.snapshotRequest` / `isSnapshotRequest`。**验收 Watch 同步必须覆盖两条冷路径**：先有便签、后装手表 App；iPhone App 没在运行——开发机上 Xcode 同时装两端并重启手表 App 会把它们都掩盖掉（B5 就是这样漏过去的，见 `docs/launch-todo.md` E5）。
- **界面显示的外部状态必须有可观察的持有者**：`body` 里只读 `@State` / `@Observable` / `@Environment` 这类 SwiftUI 能追踪的状态。ActivityKit（`Activity.activities` / `activityState`）、UserDefaults、WCSession 的状态变了都**不会**通知界面——在 `body` 里直接读它们，界面就停在旧画面，直到某次无关的重绘“碰巧”更新（手表空状态 2.1(a)、钉住图标 C12 都是这个坑，后者表现为“重进 App 才更新”）。做法：放进 `@MainActor @Observable` 的持有者（`WatchSnapshotStore`、`PinnedNotes`）——变更发生的当下主动更新，回前台 / 列表重载时再与外部真实状态对齐；单测用 `withObservationTracking` 断言“读它的界面会被通知”（见 `PinnedNotesTests`）。**外部操作是异步的时**（`Activity.end`：`unpin()` 返回 6ms 后 ActivityKit 仍报告“钉着”，约 500ms 后才变），持有者要记住“已请求、未完成”的项，别让对齐把刚改的状态拉回去。**验这类 bug 要在操作后停几秒截图、不切走 App**——切走再回来会触发重载，正好把它掩盖掉（真机上“重进就好了”就是这么来的）。
- **Live Activity 的图片尺寸（灵动岛紧凑态 / 最小化 / 手表智能叠放）**：这些小呈现能装的图片有**很低的尺寸上限**，超限**不报错**——系统归档 Live Activity 时静默把整张图换成**灰色占位圆盘**（Watch 智能叠放上那个灰圆盘就是它；iPhone 端 `PawItWidget` 扩展的日志：`Max size exceeded: 437.85x219.6; using placeholder image`，修好后是 `Image permitted`）。所以这些呈现里**只许用 `pet-<sp>-badge`（≤144px）**，不要用 480px 的 `holding`、也别用 300px 的 `front`（`front` 是否超限没验证过，按保守口径处理）；锁屏 / 横幅 / 展开态里的 480px 图实测是 permitted，不受此限。守卫在 `scripts/preflight.sh`（徽章 ≤144px、`compactLeading` 里不得出现 `petImage(`）。紧凑态标题走 Core 的 `LiveActivityText.compactTitle`（词边界 + 省略号），别再内联 `prefix(n)`。
- **手表 / CarPlay 的 Live Activity 小卡片**：主内容闭包里由 `ActivityFamilyRouter` 按 `@Environment(\.activityFamily)` 分流——`.small`（手表智能叠放、iOS 26 CarPlay）→ `SmallActivityView`，其余 → 锁屏大卡片。三个坑：① `supplementalActivityFamilies` 与 `activityFamily` 都是 iOS 18+，部署目标是 iOS 17，所以用 `supplementalSmallIfAvailable()`（`#available` 分支；`some WidgetConfiguration` 的不透明返回类型允许随 `#available` 分支变化）加 `@available(iOS 18.0, *)` 的路由视图——**一个 Widget 就够，不需要两套 Widget / 类型擦除**；iOS 17 上手表仍显示紧凑态（已被 badge 修好）。② 画布固定且**没有按钮**（手表最小 152×69.5pt、CarPlay 最小 170×78pt；CarPlay 里按钮会被禁用），整张卡就是“打开”；内容只放“一瞥”，用 `ViewThatFits` 从下往上丢行，别靠截断。③ 卡片的内容口径（下一项 / 后续项 / 完成态 / 环比例）是 Core 的 `ActivityGlance`，视图只排版——要改口径改它并改测试。
- **Commit 消息**：英语，格式 `feat/fix/test/refactor/docs: <内容>`。

## 构建与验收
- 工程由 XcodeGen 生成：改 `project.yml` 后运行 `xcodegen generate`。`PawIt.xcodeproj` 不入库，但各 target 的 `Info.plist` 与 `*.entitlements` 是**入库的生成物**——不要手改，重新生成后一并提交。
- 构建：`xcodebuild -project PawIt.xcodeproj -scheme PawIt -destination 'generic/platform=iOS Simulator' build`（**不要加 `-sdk iphonesimulator`**，会让 watchOS target 构建失败）。测试用 iOS 模拟器跑，推荐 `scripts/run-tests.sh`（封装 `xcodebuild test`，绕开“跑完却挂住”）；macOS 上的 `swift test` 预期失败（原因见 `docs/launch-readiness.md` §1）。**查警告要用全新 DerivedData**——增量构建不重编没改的文件，警告会被藏起来（做法见手册 §2）；提交前应是 0 警告。
- 签名：Team ID 默认放在被 git 忽略的 `Config/Signing.local.xcconfig`（复制 `.example` 模板）；Team ID 不是机密，团队确定后也可以直接写进 `project.yml`。
- 出包前：先构建，再运行 `scripts/preflight.sh`，要求 0 失败（⏳ 项依赖外部输入，不算失败）。
- **模拟器验证**：做法、命令、证据口径与“动用户模拟器”的规矩全在 [`docs/simulator-playbook.md`](docs/simulator-playbook.md)，**动手前先读它**。最容易得出错误结论的几条：① `simctl` 没有点按 / 滑动——`simctl openurl pawsticky://…` 会弹点不掉的 “Open in …?”，手表智能叠放要人手上滑；验深链 / 钉住用临时启动参数补丁（`TEMP-SHOT`，验完删、用 Grep 确认无残留、不提交）。② `simctl install`（哪怕原地覆盖）会**结束该 App 的所有 Live Activity**——装完要重新 Pin；`appconduitd` 还会把手表 App 误记成“未安装”（`ACXErrorDomain Code=12`，模拟器假象，原地再装一次手表 App）。③ 灵动岛内容不在模拟器截图里，卡片复制到手表要 15–30 秒；离屏渲染（`ImageRenderer`）能验排版 / 截断 / 颜色，但**不能**证明系统认不认背景色、内边距和点按——这些只能在手表 / 真机上看。④ 动用户在 Device Hub 里正在用的模拟器之前先说一声（装包会结束他钉着的卡片；往他的库里种数据要先问）。
