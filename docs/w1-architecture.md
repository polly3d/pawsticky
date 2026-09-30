# W1 架构备忘录(2026-09-30)

> 对应《开发计划-PawIt-MVP.md》§5 Task 6。W1 目标"用最小代码把三个最大技术风险证伪/证实"——全部完成。

## 1. 六个技术决定的裁决

| # | 决定 | 裁决 | 关键证据 |
|---|---|---|---|
| D1 | min iOS 17 | ✅ 维持 | 交互式 Widget 全功能可用;iPhone SE/11 均可跑 17+ |
| D2 | GRDB(SQLite/WAL)双进程 | ✅ **证实** | 4 连接×25 并发插入零丢失;16 并发翻转原子(奇偶校验);50 翻转+500 并发读一致;零 `SQLITE_BUSY`;GRDB 7.11.1(`Package.resolved` 锁定) |
| D3 | 刷新只由用户动作驱动 | ✅ **落地** | 《刷新策略表》(TimelinePlanner 文档注释):五类场景各有唯一驱动者,零行依赖系统刷新,每日预算 ≤1 次且被预计算条目兜底 |
| D4 | StoreKit 2 原生 | ⏳ W8 落地 | 隐私标签「Data Not Collected」卖点保留 |
| D5 | Cloudflare Worker 代理 | ⏳ W9 落地 | — |
| D6 | Watch = WCSession 镜像 | ⏳ **W10 D0 验证**(0.5 天 PoC) | 架构已按"Watch 只读镜像"设计;失败即降级 Watch→v1.1 |

**交互闭环总证**:用户实测——widget 点按不打开 App 即翻转、强杀 App 后仍工作、体感即时(`reviews` 级证据:领导者痛点 1 的反面)。

## 2. W1 产出一览

- 工程:XcodeGen 三 target(App/Widget/Watch)+ Core SPM;Watch 已嵌入 iOS App(W11 打包安全);CoreTests 挂入模拟器测试链(W2 前提)
- 测试:20 个(19 Core + 1 App),全绿,零警告;含 DST 双向 + 圣地亚哥午夜型时区 + 时区无关性证明
- 代码:`c85a8c3`→`18ad3b9` 共 8 个代码 commit;pbxproj 零入库
- 美术:风格冻结 B 扁平矢量+描边规格(`art/style-pack/style-notes.md`);猫/柯基角色卡;生成管线脚本(单张 ~$0.053,W1 合计 ~$0.75)

## 3. 评审循环战果(subagent-driven 流程)

3 个 Important 被独立评审抓出并修复:Watch 未嵌入(Task 1)、CoreTests 断链(Task 1)、**午夜 DST 边界超调**(Task 4,评审员主动探测任务书外时区类别发现的真 bug)。经验:**测试矩阵通过 ≠ 正确性**——矩阵选择本身是假设。

## 4. W2 前置项(必须消化,详见计划 W2 卡"Task 3 评审移交")

1. NoteRepository 持进程级唯一 DatabasePool,注入 intents(修 intent 每次开池 churn)
2. **迁移竞态修复**(双进程冷启动撞表,非 BUSY):retry-once 或 App 启动急切迁移——`w2.v1` 上线前必修
3. Widget 初始化失败不得永久缓存 nil(区分永久/瞬时错误)
4. **文件保护**:DB+WAL 边车设 `.completeUntilFirstUserAuthentication` + 真机"重启未解锁看锁屏"测试(锁屏 widget 首解前渲染)
5. "首条 Note"排序加 id 决胜;6. WAL 增长纳入 dogfooding

## 5. 工具链与流程坑(登记备查)

- **Swift Testing 函数级 `-only-testing` 静默跑零测试**(显示成功)——测试证据一律用套件级过滤并核对逐测试输出
- `local a=x b=$a` 单行多赋值在 `set -u` 下炸(gen-images.sh 已修);montage 需显式 `-font /System/Library/Fonts/Helvetica.ttc`
- SourceKit 对无工程上下文的 Swift 文件必报假错(`No such module`)——以 `xcodebuild` 为准
- **凡人眼验收先 `simctl install`**(模拟器里的 App 是上次安装的快照,测试运行不更新它)
- 计划文档三处笔误已修:NoteWidgetFamily.swift(W4 文件)×2、Task 2 引用 Task 3 的 SharedStore(时序)

## 6. 待办(真机/手动,不阻塞 W2)

- 真机部署三 target(需设备连接 + DEVELOPMENT_TEAM;两份 Apple Development 证书已在机器上)
- 真机秒表级点按延迟数字(体感即时已确认)
- 真机 50 连击挂机冒烟(模拟器版已过)
- 跨午夜视觉翻转、重启未解锁锁屏 widget(W2 文件保护项一并)
- App 图标(AI 草案+人工精修,截止 W10,并行轨)

## 7. W2 入口

周一开工动作:W2 任务卡展开为细粒度 TDD 计划;第一件事是 W2 前置项 1+2(单池 + 迁移竞态),然后才进 NoteEngine。
