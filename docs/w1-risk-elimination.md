# W1 · 风险消除 + PoC（详细记录）

> 提取自主计划 §5。完整任务卡见 `plan.md` §4。

**日期:** 2026-10-05 ~ 10-11（实际提前于 2026-09-30 完成）
**状态:** ✅ 收官

---

## Task 1: 工程骨架（命令行生成，禁止手改 pbxproj）

**Files:**
- Create: `project.yml`（XcodeGen 清单：iOS App + `PawItWidget` + `PawItWatch` 三 target + Tests；entitlements 均含 `group.com.pawit.shared`）
- Create: `Core/`（SPM 本地包）
- Create: `.gitignore`（`*.xcodeproj`、`DerivedData/`）

- [x] **Step 1.1:** `brew install xcodegen`；`swift package init --type library Core`
- [x] **Step 1.2:** 手写 `project.yml`：iOS App（SwiftUI，deploymentTarget 17.0）+ Widget Extension + watchOS App
- [x] **Step 1.3:** `xcodegen generate` 后 `xcodebuild build` 通过
- [x] **Step 1.4:** 三 target 在模拟器跑通
- [x] **Step 1.5:** Commit：`chore: scaffold 3-target app via XcodeGen + SPM Core + App Group`

> ✅ **Task 1 完成**：`c85a8c3` + 评审修复 `770f986`。规格✅质量✅。

## Task 2: PoC A — 交互式 Widget 数据闭环

- [x] **Step 2.1:** Widget 中渲染 `Button(intent: ToggleItemIntent())`
- [x] **Step 2.2:** 模拟器验证：点击勾选 → 不打开 App → 勾选状态即时变化
- [x] **Step 2.3:** 强杀 App 后 intent 仍在 Widget 进程执行
- [ ] **Step 2.4:** 秒表级延迟实测（待真机）
- [x] **Step 2.5:** Commit：`poc: interactive widget toggle loop`（`dede00d`）

> ✅ **Task 2 完成**：`dede00d`，规格✅质量✅。

## Task 3: PoC B — GRDB 双进程读写

- [x] **Step 3.1-3.4:** SharedStore 实现 + 并发测试超规格完成（4 连接×25 插入零丢失）
- [ ] **Step 3.5:** 真机 50 连击冒烟（待手动验收）
- [x] **Step 3.6:** **D2 证实** — WAL 双连接零异常
- [x] **Step 3.7:** Commit：`324f73c`

> ✅ **Task 3 完成**：评审移交六条见 W2 前置项。

## Task 4: PoC C — 刷新策略与零预算时间文字

- [x] **Step 4.1-4.4:** TimelinePlanner + 午夜翻转 + DST 边界 bug 修复

> ✅ **Task 4 完成**：`5bf65bc` + `c101fd7`。

## Task 5: 美术风格包 v1

- [x] 12 张候选 → **选定 B 扁平矢量 + 描边**（冻结于 `art/style-pack/style-notes.md`）
- [x] 猫/柯基角色卡产出

> ✅ **Task 5 完成**：`b370f5f`。

## Task 6: W1 收口

- [x] 《W1 架构备忘录》→ `docs/w1-architecture.md`
- [x] tag `week-1`

> ✅ **W1 收官**：6/6 任务完成，20 测试全绿零警告。
