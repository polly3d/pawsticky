# PawIt MVP 12 周开发实施计划

> **修订记录**:v1.1(2026-09-30)技术栈复审——SwiftData→GRDB、XCTest→Swift Testing、新增 XcodeGen 命令行生成工程(依据见 §9);v1.0(2026-09-29)经两轮独立评审通过。

> **For agentic workers:** 本计划按周组织;W1 已展开为细粒度可执行步骤(checkbox 语法),W2-W12 为任务卡。每周开工前将该周任务卡展开为当日细粒度计划再执行。执行时配合 TDD:先写失败测试,再写实现。

**Goal:** 交付商业计划书 §4.2 定义的 v1.0 MVP——便签内核做到品类最佳 + 宠物情感层 + 轻养成 + Watch Smart Stack,2026-12 圣诞软上线。

**Architecture:** 本地优先——iPhone App 与 iOS Widget 扩展共享 App Group 数据容器;**watchOS 端持有独立的只读镜像存储,由 WatchConnectivity 从手机推送最新快照**(App Group 容器不跨设备,见决定 D6)。交互式 Widget 通过 App Intents 在 Widget 内完成勾选/翻页(绕开刷新预算),宠物资产由 gpt-image-2.5 管线离线产出打包入 App,用户侧 AI 形象走 Cloudflare Worker 轻代理。**零第三方 SDK,隐私标签目标「Data Not Collected」**(领导者收集购买数据,这是差异化卖点,见商业计划 §2.1)。

**Tech Stack:** Swift 6 / SwiftUI / **GRDB(SQLite,WAL 模式,App Group 双进程)** / WidgetKit + App Intents / watchOS WidgetKit(Smart Stack + 复杂功能)/ StoreKit 2(原生,不用 RevenueCat——少一个依赖,守住零收集)/ **Swift Testing**(单测;XCUITest 仅 UI 冒烟)/ **XcodeGen(project.yml 生成工程,全命令行)/ xcodebuild + TestFlight。

**依据:** 功能范围 = `宠物便签商业计划书.md` §4.2/§4.5/§4.6;每条可靠性需求可溯源到 `research/reviews-1533254320-lows.txt` 的差评主题(§2.3 聚类)。

---

## 0. 执行约定

- **Commit 纪律**:小步提交,每个绿灯测试一个 commit,消息格式 `feat/fix/test/refactor: <内容>`;每周五打 tag `week-N`。
- **TDD 约定**:数据层、便签引擎、养成逻辑必须先写失败测试(纯逻辑,易测,用 Swift Testing);Widget/UI 用手测协议(§7)+ 少量 XCUITest 冒烟。
- **工程生成纪律**:工程由 `project.yml`(XcodeGen)定义,**禁止手改 `.xcodeproj`/`.pbxproj`**——改 target、文件、配置一律改 `project.yml` 后执行 `xcodegen generate`;`pbxproj` 与 `DerivedData/` 进 `.gitignore`。
- **每周五复盘**(30 分钟,对照当周 DoD):未完成项要么砍(进"不做清单")要么排入下周首位——**不静默滚动**。
- **范围变更规则**:新增需求必须同时写下要砍掉的等量需求,否则拒绝(单人项目的头号死因是范围蠕动)。
- **设备闸门**:提交 TestFlight 前必须通过 §7 QA 矩阵最低配置(iPhone SE 2nd gen + iPhone 11)。

## 1. 架构总览与文件结构

### 1.1 Target 布局

```
PawIt.xcodeproj
├── PawIt/                      # iOS 主 App
│   ├── App/PawItApp.swift              # 入口,scenePhase→reload widgets
│   ├── Features/
│   │   ├── Editor/                     # 便签编辑器(一秒速记流)
│   │   │   ├── EditorView.swift
│   │   │   ├── ListModeView.swift      # 清单模式(划线完成)
│   │   │   └── StylePickerView.swift   # 字体/颜色/渐变
│   │   ├── Pets/                       # 宠物选择/装扮/喂食动画
│   │   ├── Growth/                     # 轻养成仪表盘
│   │   ├── CaptureAI/                  # v1.0 beta:真宠物→卡通形象
│   │   ├── Paywall/                    # StoreKit 2 付费墙(≤1次/周规则)
│   │   └── Settings/ExportView.swift   # 数据导出(信任卖点)
│   └── ...
├── PawItWidget/                # WidgetKit 扩展(iOS)
│   ├── PawItWidgetBundle.swift
│   ├── NoteWidgetFamily.swift          # 系统 S/M/L + 锁屏 accessory + StandBy
│   ├── InteractiveControls.swift       # Button(intent:) 勾选/翻页
│   └── Renderers/
│       ├── NoteRenderer.swift          # 纯便签渲染
│       └── PetNoteRenderer.swift       # 宠物举牌渲染(签名视觉)
├── PawItWatch/                 # watchOS App(v1.0:壳 App + Smart Stack/复杂功能)
│   ├── PawItWatchWidget.swift          # 复用共享渲染,表盘尺寸调优
│   └── WatchMirror/WatchStore.swift    # Watch 侧只读镜像存储(D6,App Group 不跨设备)
├── Core/                       # ⭐ 三 target 共享的纯逻辑层(最多单测的地方)
│   ├── Models/                         # Note/NoteItem/PetProfile/GrowthState
│   ├── Store/
│   │   ├── SharedStore.swift           # App Group GRDB(SQLite/WAL)数据库(单例接入点)
│   │   ├── NoteRepository.swift        # 增删改查+版本历史+导出
│   │   └── HistoryLog.swift            # 7 天回滚日志(append-only)
│   ├── Sync/
│   │   └── NoteSnapshotSync.swift      # WCSession 封装:手机→Watch 快照推送(D6)
│   ├── Engine/
│   │   ├── NoteEngine.swift            # 勾选语义/划线/排序/午夜翻转
│   │   └── GrowthEngine.swift          # 喂养进度/连击/装扮解锁
│   ├── Intents/
│   │   ├── ToggleItemIntent.swift      # Widget 内勾选
│   │   ├── CycleNoteIntent.swift       # Widget 内翻页
│   │   └── AppendNoteIntent.swift      # Siri/快捷指令速记
│   └── Paywall/Gate.swift              # 功能门控 + 弹窗频控
└── PawItTests/                 # Swift Testing(Engine/Store 全覆盖)
    ├── NoteEngineTests.swift
    ├── GrowthEngineTests.swift
    └── HistoryLogTests.swift
```

### 1.2 关键数据流(可靠性护城河的代码化)

```
用户在 Widget 点勾选
  → ToggleItemIntent.perform()          # App Intents,在 Widget 进程内执行
  → Core/Store 写入 App Group 容器       # 无网络、无 iCloud 等待
  → 系统自动重渲染该 Widget               # iOS 17+ 交互式 Widget 特性,不消耗刷新预算
```

```
用户在 App 内编辑便签
  → 每 300ms 防抖自动落盘(逐键安全)
  → scenePhase = .background 立即全量落盘 + WidgetCenter.reloadTimelines
  → Widget 从 App Group 快照渲染,永远不空窗
```

## 2. 六个技术决定(先定死,避免中途摇摆)

| # | 决定 | 理由 | W1 验证点 |
|---|---|---|---|
| D1 | **最低系统 iOS 17.0**(与领导者持平) | 交互式 Widget 是体验护城河的根基;iOS 16 以下用降级 UI 的维护成本 > 收益 | — |
| D2 | **GRDB(SQLite)存 App Group 容器**,App 与 Widget 扩展双进程读写(WAL 模式 + busyTimeout) | v1.1 复审反转:SwiftData 生产风险成社区共识——schema hash mismatch 可 brick store、`ModelContainer` 创建失败处理(Apple 示例竟是 `fatalError`,在 Widget 进程致命)、无 store 端聚合(依据见 §9)。我们查询极简(便签 CRUD + 日志)、双进程、**零丢数据是第一卖点**——正是 SQLite 甜区,GRDB 久经考验 | **PoC B:GRDB 双进程并发写读冒烟**(WAL/锁配置验证) |
| D3 | **刷新策略:内容变更永远由"用户动作"驱动**(intent/前台),绝不为展示效果依赖系统刷新 | 刷新预算 ~40-70 次/天是领导者"不刷新"差评的技术根因(`reviews-1533254320-lows.txt` 痛点 1)。倒计时等时间文字用 `Text(timerInterval:)`(自更新,零预算消耗) | PoC C |
| D4 | **StoreKit 2 原生**,不用 RevenueCat | 零第三方数据收集 → 隐私标签「Data Not Collected」(领导者是"Purchases 收集"),信任卖点直接写进 ASO 首图 | — |
| D5 | **AI 代理用 Cloudflare Worker**(单端点,持有 gpt-image-2.5 key) | App 内嵌 key 必被提取;Worker 免费额度 10 万请求/天足够;限流用 DeviceCheck + 收据校验 | W9 联调 |
| D6 | **Watch 数据 = WatchConnectivity 镜像**:手机端 `NoteSnapshotSync` 以 `updateApplicationContext` 推送最新快照,Watch 存本地只读镜像供 Widget 渲染 | App Group 容器**不跨设备**(Watch 上 `containerURL` 返回的是手表自己的空容器,静默失败);WCSession 异步尽力送达,故验收是"秒级收敛"而非"零陈旧"(§7-AW)。PoC 失败 → 按降级阶梯 Watch 整体推迟 v1.1 | W10 D0(0.5 天 PoC) |

## 3. v1.0 不做清单(范围纪律,来自商业计划 §4.3)

- iCloud 多设备同步(v1.1;本地导出/导入兜底)
- 情侣共养(v1.2)| 宠物世界/公益联动(v2.0)
- 完整 watchOS App 语音速记(v1.1;v1.0 只做 Smart Stack + 复杂功能)
- 8 语言本地化(v1.0 仅 EN + zh-Hans)| Android | Lottie 动画(Widget 不支持,庆祝动画只在 App 内用 SwiftUI 原生实现)
- 预注册账号体系(永不;本地优先是卖点)

## 4. 12 周排期总表

| 周 | 日期(2026) | 主题 | 硬交付物(DoD) | 商业计划对应 |
|---|---|---|---|---|
| **W1** | 10/05-10/11 | **风险消除 + PoC** | 3 个 PoC 在真机通过 + 架构决定备忘录 + 美术风格包 v1 | §4.4/§4.5 |
| W2 | 10/12-10/18 | 数据层 + 便签引擎 | Engine/Store 单测全绿;6 宠物角色卡定稿 | §4.2 内核 |
| W3 | 10/19-10/25 | 编辑器 UI | 一秒速记流可用;自动保存演示(杀进程零丢失) | §4.2 |
| W4 | 10/26-11/01 | Widget 家族(静态) | S/M/L+锁屏+StandBy 全家族渲染,午夜翻转正确 | §4.2 |
| W5 | 11/02-11/08 | 交互式 Widget + Intents | Widget 内勾选/翻页真机 <100ms;Siri 速记可用 | §4.4 |
| W6 | 11/09-11/15 | 宠物层集成 | 宠物举牌渲染上线;喂食动画;全部资产入包 | §4.2 宠物层 |
| W7 | 11/16-11/22 | 轻养成 + 分享卡片 | 连击/解锁逻辑测试全绿;IG Story 卡片导出 | §4.2 养成 |
| W8 | 11/23-11/29 | 商业化 | 沙盒收据三档购买通过;弹窗频控 ≤1/周 | §6 |
| W9 | 11/30-12/06 | AI 形象 beta + 后端 | Worker 上线;上传→生成→展示全链路;**feature flag 可关** | §4.5 |
| W10 | 12/07-12/13 | watchOS | Smart Stack + 3 款复杂功能真机通过 | §4.6 |
| W11 | 12/14-12/20 | QA 矩阵 + TestFlight 公测 | 200 人公测;崩溃率 <0.1%;ASO 资产齐 | §10.3 |
| W12 | 12/21-12/27 | 修复 + 软上线 | 分区上线(NZ→CA→US);监控仪表盘就位 | §10.1 |

**预定的降级阶梯**(进度落后时按序砍,砍前不打架):W9 AI 形象整体 flag 关闭(→v1.1)→ W10 Watch(→v1.1)→ 分享卡片降级为纯截图。**永不可砍**:W1-W5(可靠性是产品本体)。

**并行轨(非开发,每周 ≤3 小时,避免撞上 W7-W11 冲刺):**
- **App 图标**:AI 草案 + 一次人工精修,截止 W10 末(W11 ASO 资产依赖它;商业计划 §4.5 边界项)
- **TikTok build-in-public**:W6 起(≈上线前 6 周)持续到软上线,内容源 = 每周开发/美术产出(商业计划 §8.1①)
- **TestFlight 公测招募**:W9 启动(非关键路径,避开 W11 假期周;定向领导者差评用户)

---

## 5. W1 详细任务(关键路径,逐条执行)

> W1 的唯一目标:用最小代码把三个最大技术风险证伪/证实。本周代码允许丑,不允许含糊。

### Task 1: 工程骨架(命令行生成,禁止手改 pbxproj)

**Files:**
- Create: `project.yml`(XcodeGen 清单:iOS App + `PawItWidget` + `PawItWatch` 三 target + Tests;entitlements 均含 `group.com.pawit.shared`)
- Create: `Core/`(SPM 本地包)
- Create: `.gitignore`(`*.xcodeproj`、`DerivedData/`)

- [x] **Step 1.1:** `brew install xcodegen`;`swift package init --type library Core`(纯逻辑层,独立于 App 可测)
- [x] **Step 1.2:** 手写 `project.yml`:iOS App(SwiftUI,deploymentTarget 17.0)+ Widget Extension + watchOS App,三 target 均引用本地 `Core` 包并声明 App Group entitlement
- [x] **Step 1.3:** `xcodegen generate` 后 `xcodebuild -scheme PawIt -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` 通过;Watch scheme 同样验证
- [x] **Step 1.4:** 三 target 在模拟器跑通(App、空 Widget、Watch App;真机步骤待设备连接 + 签名配置后补验,见备忘)
- [x] **Step 1.5:** Commit:`chore: scaffold 3-target app via XcodeGen + SPM Core + App Group`(仅入库 project.yml 与源码,pbxproj 不入库)

> ✅ **Task 1 完成(2026-09-30)**:`c85a8c3` + 评审修复 `770f986`(Watch 嵌入 + CoreTests 挂入模拟器测试链)。规格评审与质量评审(两轮)均通过;零警告;3 测试全绿。遗留:真机验证待签名;PawItTests 宿主链接待 W2 App 逻辑出现时添加。

### Task 2: PoC A —— 交互式 Widget 数据闭环(风险:意图→落盘→重渲染)

**Files:**
- Create: `Core/Sources/Core/Intents/ToggleItemIntent.swift` + `Core/Sources/Core/ToggleState.swift`(App Group UserDefaults 桥接,Task 3 落地 SharedStore 后删除)
- Modify: `PawItWidget/PawItWidgetBundle.swift`(计划原文写的 NoteWidgetFamily.swift 系 W4 才创建的文件,此处为笔误;实际改 WidgetBundle)

- [x] **Step 2.1:** 在 Widget 中渲染一个 `Button(intent: ToggleItemIntent())`:

```swift
struct ToggleItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Item"
    func perform() async throws -> some IntentResult {
        let store = SharedStore.shared     // App Group 容器
        store.toggleFirstItem()
        return .result()                   // 返回后系统自动重渲染本 Widget
    }
}
```

- [ ] **Step 2.2:** 真机验证:点击勾选 → **不打开 App** → 勾选状态即时变化;秒表记录延迟(待手动/真机:模拟器 springboard 加 widget 无法自动化,已备 4 步指引)
- [ ] **Step 2.3:** 验证杀 App 场景:强杀主 App 后重复 Step 2.2(intent 仍在 Widget 进程执行)(同上,待手动)
- [ ] **Step 2.4:** 在备忘录记录实测延迟(预期 <100ms)与任何异常 → 这是 D2/D3 的决策证据(待 2.2/2.3)
- [x] **Step 2.5:** Commit:`poc: interactive widget toggle loop`(`dede00d`;真机项未做,如实去掉 on device 后缀)

> ✅ **Task 2 实现完成(2026-09-30)**:`dede00d`,规格评审✅ + 质量评审✅(Yes,0 Critical/Important)。单测证明 intent→App Group 套件闭环(模拟器不强制权利,设备级验证随 2.2/2.3)。评审 Minor 项移交 Task 3:删除 ToggleState 并 grep `poc.isToggled` 归零;W1 备忘录(Task 6)记录计划内 SharedStore 时序笔误。

### Task 3: PoC B —— GRDB 双进程读写(验证 D2 的配置正确性)

**Files:**
- Create: `Core/Store/SharedStore.swift`(真实实现)
- Test: `Tests/SharedStoreTests.swift`(Swift Testing)

- [x] **Step 3.1:** 写失败测试(Swift Testing 语法):App 进程写入 Note → 同一 App Group 路径的第二个独立连接(模拟 Widget 进程)可读到:

```swift
import Testing
@testable import Core

@Test func crossProcessRead() throws {
    let storeA = SharedStore(path: .appGroupDB)   // DatabasePool, WAL
    try storeA.insert(Note(text: "hello"))
    let storeB = SharedStore(path: .appGroupDB)   // 独立连接 = 模拟 Widget 进程
    #expect(try storeB.countNotes() == 1)
}
```

- [x] **Step 3.2:** `xcodebuild test -scheme PawIt -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → 预期 FAIL(`SharedStore` 未实现)——TDD 红灯实证
- [x] **Step 3.3:** 实现 `SharedStore`:GRDB `DatabasePool`(自动 WAL)+ `busyMode = .timeout(2)`(GRDB 7 改名)+ `DatabaseMigrator`(`w1.v1` 建 note 表);文件名落地为 `pawit.sqlite3`(优于计划的 store.sqlite,记录在案)
- [x] **Step 3.4:** 测试转绿;并发测试超规格完成:4 连接×25 并发插入零丢失、16 并发翻转奇偶校验不变量、50 翻转 + 500 并发读全一致、WAL/表结构用 PRAGMA 断言
- [ ] **Step 3.5:** 真机挂机冒烟:Widget 勾选连续 50 次(模拟器级已过:50 翻转 + 并发读零丢失;真机版随手动验收清单)
- [x] **Step 3.6:** **决策点**:**D2 证实**——WAL 双连接零异常、零 workaround、无需降级单写者架构
- [x] **Step 3.7:** Commit:`feat: shared GRDB store in App Group, WAL dual-process (PoC B verified)`(`324f73c`)

> ✅ **Task 3 完成(2026-09-30)**:`324f73c`(10 文件 +387/−72,含 Package.resolved 锁 GRDB 7.11.1)。规格✅质量✅(Yes)。评审移交项已登记:①intent 每次开新池的 churn → W2 NoteRepository 进程级单池接管 ②双进程冷启动迁移竞态(败者 CREATE TABLE 撞表,非 BUSY)→ W2 加 retry-once 或 App 启动时急切迁移,**必须在 `w2.v1` 迁移上线前修** ③widget 把初始化失败永久缓存为 nil → W2 区分错误类型/重试 ④**文件保护级别**(DB + WAL/-shm 边车设 `.completeUntilFirstUserAuthentication`,否则锁屏 widget 首解前可能 SQLITE_IOERR)→ W2 必做 + 重启未解锁测试。

### Task 4: PoC C —— 刷新策略与零预算时间文字

**Files:**
- Create: `Core/Sources/Core/Store/TimelinePlanner.swift`(纯逻辑 + 《刷新策略表》文档注释)
- Test: `Core/Tests/CoreTests/TimelinePlannerTests.swift`
- Modify: `PawItWidget/PawItWidgetBundle.swift`(计划原文 NoteWidgetFamily.swift 系 W4 文件,笔误同 Task 2)

- [x] **Step 4.1:** 实现 `Timeline(policy: .after(明日00:01))` + 预生成双条目(今天 + 明日 00:01 翻转);跨午夜翻转以注入时钟的纯逻辑测试验证(含 NY DST 双向 + 圣地亚哥午夜 DST 类时区),真机视觉翻转列入手动清单
- [x] **Step 4.2:** 渲染 `Text(timerInterval:)` 倒计时(计划原文 `Text(date, style:.timer)` 的 widget 安全变体),零刷新预算;每秒跳动的视觉确认列入手动清单
- [x] **Step 4.3:** 《刷新策略表》已作为 TimelinePlanner 文档注释交付:五类场景各有唯一驱动者,零行依赖系统主动刷新,每日预算至多 1 次(午夜续链)且被预计算条目兜底
- [x] **Step 4.4:** Commit:`poc: timeline policy + zero-budget timer text`(`5bf65bc`)+ 评审修复 `c101fd7`(午夜 DST 边界 bug:改用 `dateInterval(of:.day).end`,圣地亚哥类时区实测)

> ✅ **Task 4 完成(2026-09-30)**:`5bf65bc` + `c101fd7`。规格✅(含 00:01 统一裁定:优于计划字面混合)质量✅(修复后 Approved)。评审亮点:主动探测任务书外时区类别(午夜型 DST)抓到真实超调 bug。遗留(登记 W4/备忘录):`nextMidnight` 方法注释补"边界=日界(含 01:00 类)"说明;`.tertiary` 倒计时真机可读性待手动验收。

### Task 5: 美术风格包 v1(与代码并行,gpt-image-2.5)

- [ ] **Step 5.1:** 用 gpt-image-2.5 产出 **3 套候选风格**(每套:猫+狗各 2 姿势,"举着空白便签"),风格差异要大(如:厚涂贴纸风 / 扁平矢量风 / 手绘水彩风)
- [ ] **Step 5.2:** 按 §4.5 checklist 验收(线条/比例/举牌透视),选 1 套,**冻结风格包**(提示词 + 4 张定稿参考图存 `art/style-pack/`)
- [ ] **Step 5.3:** 选中风格下产出猫、狗的**角色卡**(正/侧/背三面)——后续一切姿势以角色卡为参考图
- [ ] **Step 5.4:** Commit(art 目录也入库):`art: freeze style pack v1 + cat/dog character cards`

### Task 6: W1 收口

**已积累的备忘录素材(评审移交,写入 Step 6.1 备忘录):**
- 计划内时序笔误:Task 2 原文引用了 Task 3 才有的 `SharedStore`;Task 2/4 文件清单误写 W4 的 NoteWidgetFamily.swift(已在文档修正)
- 措辞诚实:commit "(PoC B verified)" 的"验证"指模拟器级双连接代理;真机跨进程 + GRDB 多进程 BUSY 边界(如 last-close checkpoint、崩溃恢复)仅真机可测
- 待办的手动/真机验收清单:Task 2 Steps 2.2-2.4(springboard 点按、杀 App、延迟实测)、Task 3 Step 3.5 真机 50 连击、Task 1 真机三 target 部署、Task 4 倒计时每秒跳动 + 跨午夜视觉翻转 + `.tertiary` 可读性
- W2 前置项见 W2 卡"Task 3 评审移交"六条(单池、迁移竞态、失败缓存、文件保护、排序决胜、WAL 监控)
- **姿态裁定**:Core 库中守卫式 `fatalError`(仅系统不可表示日期可达,如 9999 年边界)优于 throw 仪式或静默错误回退——错误回退对 D3 比崩溃更糟(错午夜 = 陈旧日)。与 D2 否决 SwiftData 的 `fatalError` 示例并不矛盾:那是**可达路径**(容器创建失败),这是**不可达路径**
- **工具链坑**:xcodebuild 对 Swift Testing 的**函数级** `-only-testing:.../testName` 会静默跑零个测试(显示成功)——必须用套件级过滤或全量运行;CI 与后续任务的测试证据一律核对逐测试输出行
- W4 顺手项:`nextMidnight` 方法注释补"返回日界(午夜型 DST 日为 01:00)"说明;`makeEntry` 的 `entries(now:)[0]` 强索引在家族增多时提升为命名访问器 `todaySlot(now:)`;NoteEngine 的午夜语义消费 TimelinePlanner 的日界定义(单一事实源,防两处漂移)

- [ ] **Step 6.1:** 写《W1 架构备忘录》(1 页):D1-D5 全部"证实/证伪"结论 + 实测数据(D6 的验证点在 W10 D0,备忘录中登记计划)+ 上述素材
- [ ] **Step 6.2:** 打 tag `week-1`;备忘录入库
- [ ] **Step 6.3:** W2 任务卡展开为细粒度计划(下周一开工前)

---

## 6. W2-W12 任务卡

> 格式:目标 / 核心任务 / DoD(验收标准) / 测试。每周五对照 DoD 复盘。

### W2 · 数据层 + 便签引擎
**核心任务:** `Note`(**含 `dueDate` 字段**,§4.2 到期提醒的数据基础)/`NoteItem`/`PetProfile`/`GrowthState` 模型;`NoteRepository`(CRUD + 7 天 `HistoryLog` append-only 回滚 + 导出/导入:JSON,可选口令加密——统一口径,§7-P2);`NoteEngine` 勾选语义(经典划线样式保留——差评点 *"[1★ v4.6.3 2025-06-07] Liked it better before the update… able to cross the things on the list instead of a ✅"* `[reviews-1533254320-lows.txt]`)、排序、午夜翻转、到期语义;剩余 4 只宠物角色卡。
**DoD:** Engine/Store 单测覆盖 ≥90%,全绿;`xcodebuild test` 通过;导出的 JSON 重新导入数据一致。
**测试:** `NoteEngineTests`(勾选/划线/排序/午夜/**到期语义**),`HistoryLogTests`(回滚窗口),`SharedStoreTests`(GRDB `DatabaseMigrator` 迁移)。
**注意事项:** ~~GRDB 引入后提交 `Core/Package.resolved` 入库~~(Task 3 已完成,锁 7.11.1);为 PawItTests 增加 `- target: PawIt` 宿主链接,使 App 层逻辑可测(Task 1 评审遗留项)。**Task 3 评审移交(必须在此周消化):**
1. `NoteRepository` 持**进程级唯一 DatabasePool** 并注入 intents(intent 现每次 `appGroup()` 开新池 + 跑迁移,churn 在 W5 延迟闸门上会爆);
2. **迁移竞态修复**(双进程冷启动同时跑 migrator,败者 `CREATE TABLE` 撞表且非 BUSY):init retry-once 或 App 启动急切迁移——`w2.v1` 上线前必修;
3. Widget 初始化失败不得永久缓存 nil:区分"容器不可用(永久)"与"迁移/瞬时失败(可重试)";
4. **文件保护**:DB 与 WAL/-shm 边车显式设 `.completeUntilFirstUserAuthentication` + 真机"重启后未解锁看锁屏 widget"测试(锁屏 widget 首解前渲染,保护级别不匹配 = 经典 SQLITE_IOERR 来源);
5. "首条 Note"排序无 tiebreaker(createdAt 相同则不确定)——NoteEngine 定义排序语义时加 id 决胜;
6. WAL 增长监控纳入 dogfooding;GRDB 池读者已内置 `readonlyBusyMode=.timeout(10)`,跨进程 BUSY 排查时知悉。

### W3 · 编辑器 UI
**核心任务:** Widget 点击 → 编辑器**光标直达正文,无命名步骤**(差评点 *"[2★ v5.0.0 2025-09-29] requirement to name a note before it will save"*)；逐键防抖 300ms 落盘;`scenePhase=.background` 即时落盘;清单模式;字体/颜色/渐变选择器;**到期提醒设置 UI + 通知权限申请流 + `UNUserNotificationCenter` 调度引擎**(§4.2 到期提醒;本地通知零刷新预算,与 D3 协同);深色模式全元素对比度校验;Dynamic Type。
**DoD:** 演示脚本——输入中途强杀 App,重开零丢失;设 2 分钟后到期的提醒,锁屏收到通知并点击跳回该便签;VoiceOver 走查编辑主流程。
**测试:** 手测协议 §7-P1;`Repository` 落盘时机单测;提醒调度单测(schedule/cancel/编辑即替换——经协议封装注入 `UNUserNotificationCenter` 假实现)。

### W4 · Widget 家族(静态渲染)
**核心任务:** `NoteWidgetFamily` 覆盖 systemSmall/Medium/Large + accessoryCircular/Rectangular/Inline(锁屏)+ StandBy;时间线预生成(午夜翻转);新旧便签切换布局。
**DoD:** 全家族在 iPhone SE(最小屏)、16 Pro Max(最大屏)与 **iPad 10th**(§4.2 首条要求,提前 7 周暴露布局问题)截图入库无裁切遮挡;锁屏深色背景可读性人工校验(差评点 *"[3★ v5.0.4 2026-01-13] Dark mode"*);跨午夜真机验证翻转。
**测试:** 手测协议 §7-W;渲染快照存 `qa/screenshots/`。

### W5 · 交互式 Widget + App Intents
**核心任务:** `ToggleItemIntent`/`CycleNoteIntent`/`AppendNoteIntent`(Siri + 快捷指令:"嘿 Siri,买猫粮加进清单")接入真实 Repository;Widget 内勾选动画(划线);App 前台变更后 `WidgetCenter.reloadTimelines`。
**DoD:** 真机勾选延迟 <100ms;强杀 App 后 intent 仍工作;Siri 速记端到端;**连续 50 次勾选零数据丢失**(可靠性卖点的验收仪式,录屏存档)。
**测试:** Intent 单测(mock store);手测协议 §7-I。

### W6 · 宠物层集成
**核心任务:** `PetNoteRenderer`(宠物举牌布局引擎:姿势×心情×便签尺寸的状态机);6 宠物×8-10 姿势全资产入包(PNG,三倍率,asset catalog);**12 件装扮图同管线产出并入包**(W7 解锁逻辑使用);App 内喂食庆祝动画(SwiftUI 原生);宠物音效/触感(可关)。
**DoD:** 资产包体积增量 <15MB(对照领导者 97.8MB 的包袱,`lookup-1533254320.json`);每宠物在 3 种 Widget 尺寸下无构图破碎;动画在 SE 上不掉帧。
**测试:** 布局引擎状态机单测;资产完整性脚本(缺姿势**或缺 12 件装扮**即 CI 失败)。

### W7 · 轻养成 + 分享卡片
**核心任务:** `GrowthEngine`(完成→喂食进度;连击→装扮解锁 12 件;**断签不惩罚**——Finch 原则);成长只挂任务完成不挂 App 打开;分享卡片导出(IG Story 1080×1920 + 水印)。
**DoD:** 养成逻辑单测全绿(含时区/跨午夜用例);卡片导出到相册端到端;「设置→关闭养成」开关可用(尊重纯工具用户)。
**测试:** `GrowthEngineTests`(连击/解锁/断签/时区)。

### W8 · 商业化
**核心任务:** StoreKit 2 三档商品($1.49/月、$5.99/年 7 天试用、$14.99 买断);`Gate` 功能门控;付费墙 UI;**弹窗频控:主动弹 ≤1 次/周**(差评点 *"[3★ v5.0.5 2026-02-08] Pop every time I edit a sticky note"*,反着做);买断承诺文案入 App 描述。
**DoD:** 沙盒环境三档购买/恢复购买/退款状态全通过;频控逻辑单测;免费档完整可用清单走查(无限便签+2 宠物+全核心编辑)。
**测试:** `GateTests`(门控矩阵×频控);沙盒手测录像。

### W9 · AI 形象 beta + 轻后端
**核心任务:** Cloudflare Worker(单端点:DeviceCheck 限流 → gpt-image-2.5 以 §4.5 风格包为参考 → 返回图;不落盘用户原片);App 内上传→生成→设为我的宠物流;生成结果本地缓存;**整功能经 `Gate` 门控为 Premium**(§4.2 商业化清单)。
**DoD:** 全链路端到端;限流生效(超额返回明确文案);隐私标签草稿确认"照片不存储";**远程 feature flag 可整体关闭**(降级阶梯第一级)。
**测试:** Worker 单测(限流/错误路径);端到端手测;flag 关闭态走查。

### W10 · watchOS
**核心任务:** **D0(0.5 天)WatchConnectivity 同步 PoC**(决定 D6):手机改数据 → `NoteSnapshotSync.updateApplicationContext` 推送 → Watch 镜像更新 → Smart Stack 重渲染;PoC 通过后:`PawItWatch` 壳 App + Smart Stack widget(复用 `Core` 渲染,表盘尺寸调优)+ 表盘复杂功能(accessory 家族);**整体经 `Gate` 门控为 Premium**(§4.6)。规模预估:同步层约 1.5-2 天。
**DoD:** 同步 PoC 通过(失败即触发降级阶梯:Watch → v1.1);Watch 真机 Smart Stack 出片;§7-AW 同步标准;44mm/41mm 两种尺寸校验;未购 Premium 时 Watch 功能按门控呈现。**周三降级检查点**:D0 同步 PoC 若未通过,当日决策 Watch 顺延 v1.1,余下半周转投 W11 QA 前置——不等周五复盘。
**测试:** 手测协议 §7-AW(手机连续改 10 次,Watch ≤10s 收敛;>30s 陈旧 = 失败)。

### W11 · QA 矩阵 + TestFlight 公测
**核心任务:** §7 QA 矩阵全量执行;TestFlight 外测 200 人(**定向招募领导者差评用户**——Reddit r/ios 等,话术:"被不刷新坑过的来试试");评分请求逻辑(仅在"完成第 N 次勾选"等正反馈时刻触发);ASO 资产(截图 6+1 张,首图打"宠物举牌 + $14.99 买断 + 永不丢笔记"三卖点;EN/zh-Hans 文案)。
**DoD:** 崩溃率 <0.1% 且崩溃免费报告清零;SE/11 全通过;公测反馈分类进下周期;ASO 资产入 App Store Connect 草稿。
**测试:** §7 全矩阵;MetricKit 崩溃/卡顿看板。

### W12 · 修复 + 软上线
**核心任务:** 公测 P0/P1 修复;**分区分批上线**(NZ→CA→US:按 App Store Connect 供应地区逐步开放、手动推进——注意官方 Phased Release 只作用于既有用户的自动更新,不适用于首发);ASO 关键词首轮提交;监控就位(MetricKit 崩溃、Xcode Analytics、手动"不刷新"反馈标签分类)。
**DoD:** 美区正式可见;首发周评分 ≥4.5;`week-12` tag;《上线后 30 天作战表》发布(对应商业计划 §10.3 KPI 节奏)。
**测试:** 线上回归(每日前 20 条评论人工分类,标记"不刷新/丢数据"占比——必须 <10%,否则当周热修)。

---

## 7. QA 矩阵与手测协议

**设备最低矩阵:** iPhone SE 2nd/3rd · iPhone 11 · iPhone 16 Pro · iPad 10th · Watch SE 2 / S9

| 协议 | 场景 | 通过标准 |
|---|---|---|
| P1 速记 | 点 Widget→输入→杀进程→重开 | 零丢失,无需命名 |
| P2 换机 | 导出(JSON,可选口令加密)→新设备导入 | 数据完整含宠物/养成状态 |
| W 刷新 | App 内改字→回桌面 | ≤2s 更新(前台 reload 链路) |
| I 交互 | 强杀 App 后 Widget 勾选 | 正常,<100ms |
| W-午夜 | 跨 00:00 放置 Widget | 日期/清单一键翻转,无陈旧 |
| AW 同步 | 手机连续改 10 次(D6 WCSession 链路) | Watch ≤10s 收敛到最新(异步尽力送达);>30s 陈旧 = 失败 |
| DW 深色 | 深色模式 + 锁屏两种壁纸 | 全元素可读 |

## 8. 里程碑闸门(对照商业计划 §10.3)

| 闸门 | 时间 | 通过线(未达即触发降级阶梯) |
|---|---|---|
| G1 架构 | W1 末 | 3 个 PoC 全部证实,或已完成 GRDB 切换 |
| G2 可靠 | W5 末 | 50 连击零丢失;勾选 <100ms;午夜翻转正确 |
| G3 完整 | W8 末 | 沙盒购买全通过;免费档走查合格 |
| G4 发布 | W11 末 | QA 矩阵全绿;崩溃率 <0.1%;公测 200 人 |
| G5 线上 | 上线 +30 天 | 评分 ≥4.5;"不刷新/丢数据"类反馈占比 <10% |

## 9. 技术栈复审依据(2026-09-30 搜索验证,v1.1)

- **GRDB 优先于 SwiftData**:Fatbobman《Key Considerations Before Using SwiftData》(2025-03)——特性缺口与迁移纪律成本;Michael Tsai "Returning to Core Data" 系列开发者撤离报告;Apple Developer Forums(2026-05/06)——SwiftData + App Group + Widget 扩展仍有容器共享与 schema hash mismatch 活跃问题,`ModelContainer` 创建失败示例竟是 `fatalError`(Widget 进程致命);HackerNoon《SwiftData, Core Data, or GRDB: Choose by the Queries》(2026-08)——按查询模式选存储。本项目:查询极简 + 双进程 + 零丢失容忍 → GRDB/SQLite 甜区。
- **Swift Testing**:Xcode 26 新项目默认测试框架;`@Test`/`#expect`、默认并行执行;XCUITest 仍为 UI 测试唯一选项,保留给冒烟。
- **XcodeGen 命令行生成**:AI 辅助开发社区共识——纯文本 manifest(YAML)对 LLM 可读、可 diff、可确定性再生成;`.pbxproj` 对 LLM 编辑与 git 合并均不友好。Tuist 功能更强(缓存/模板,面向团队规模化),solo + AI 选轻量的 XcodeGen。
- **min iOS 17 维持**:TelemetryDeck 2026 数据——iOS 17+ 累计覆盖约 90%;行业常见 min 16-17;Apple 硬性要求仅 min iOS 13 + Xcode 26 构建。iOS 17 与领导者持平且保住交互式 Widget(决定 D1)。
- **StoreKit 2 维持**:单平台 +「Data Not Collected」隐私标签是硬卖点(第三方 IAP SDK 必然上报购买事件,与零收集冲突);RevenueCat 留待需要 A/B 实验或多平台时再评估(决定 D4)。

---

*执行入口:每周一将该周任务卡展开为当日细粒度计划(TDD 步骤)。W1 已展开完毕,可直接从 Task 1 开始。*
