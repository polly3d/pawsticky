# 模拟器验证手册

> 怎么用模拟器验证 PawSticky、**模拟器能证明什么 / 证明不了什么**，以及动用户正在用的模拟器时的规矩。
> `CLAUDE.md` 只留最容易让人得出错误结论的几条陷阱；做法、命令和证据口径都在这里。
> 进度以 [`launch-todo.md`](launch-todo.md) 为准；这里只讲"怎么验"，不记进度。

## 0. 先判断：这件事模拟器能验吗

| 想验证的 | 模拟器 | 怎么验 / 谁来验 |
|---|---|---|
| 数据层、业务逻辑 | ✅ | 单测：`scripts/run-tests.sh`（§2） |
| 列表 / 编辑器 / 设置页的版面与状态 | ✅ | `simctl io … screenshot`（§7） |
| 深链（冷启动 / 热启动的落点） | ✅ 间接 | 临时启动参数补丁（§3）；`simctl openurl` 的确认框点不了 |
| Watch 同步（含两条冷路径） | ✅ 配对模拟器，有假象 | §4 |
| Live Activity 小呈现里的图片有没有被系统降级 | ✅ | 看日志（§5） |
| 灵动岛紧凑态的**画面** | ❌ 模拟器截图里只有一个空药丸 | 日志 + 离屏渲染（§6）；实物要真机 |
| 手表智能叠放里的**真实卡片** | ❌ 唤出它要在手表上上滑，`simctl` 没有点按 / 滑动 | 请用户在 Device Hub / 真机上看；或给 Computer Use 授权（§1） |
| 任意画布尺寸下的排版 / 截断 / 颜色 | ✅ 离屏渲染 | §6 |
| 系统怎么装裱它（背景色认不认、内边距、点按） | ❌ | 只能手表 / 真机 |
| 真机独有：签名与 App Group 容器、交互式 Widget 点击、WCSession 真实连通性、系统"存储到文件"面板 | ❌ | 真机冒烟（B5）/ TestFlight（E2） |

**原则：** 没验证的就写"没验证"，并给用户一份"请看"清单（写法见 `launch-todo.md` 的 C12 / C13 条目）；**不要拿离屏渲染冒充系统截图**。

## 1. 环境与规矩

- Xcode 27 没有 Simulator.app——模拟器窗口在 **Device Hub**（`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`）。`xcrun simctl` 操作的是**同一批模拟器**：在 Device Hub 里已经启动的设备，命令行照样能装包、截图、读日志、改它的库，不需要窗口。
- 找设备：`xcrun simctl list devices available`、`xcrun simctl list pairs`（一对 iPhone ↔ Watch 才有 Watch；单个 iPhone 模拟器没有）。UDID 因机器而异，**别写死进仓库**。
- 本机惯例的分工：① **测试机**——一台**关机**的 iPhone，专给 `xcodebuild test`，不打扰别的；② **配对机**——一对 iPhone ↔ Watch，验同步 / Live Activity，优先用**自己的**那对；③ 用户在 Device Hub 里正在用的设备。
- **动用户正在用的模拟器之前，先说一声，并守这几条：**
  1. `simctl install`（哪怕原地覆盖）会**结束该 App 的所有 Live Activity**——用户停在手表上的卡片会当场过期；
  2. 往他的库里种数据要先问；种了就记下来，收工时告诉他有哪些、怎么删；
  3. 装进去的若是带临时补丁的构建，要告诉他"这不是仓库里的代码"；
  4. 还原不了的改动，收工时列给他。
- **点屏 / 滑屏：** `simctl` 没有这两个动作。Computer Use 要给 "Cursor Computer Use" 开 Accessibility + Screen Recording 权限才能驱动 Device Hub；没授权时不要指望它（`computer_check_permissions` 可查）。

## 2. 构建与测试

```bash
xcodegen generate                                   # 改了 project.yml 之后
xcodebuild -project PawIt.xcodeproj -scheme PawIt -destination 'generic/platform=iOS Simulator' build   # 不要加 -sdk iphonesimulator
scripts/run-tests.sh                                # 全量测试，见下
scripts/preflight.sh                                # 先构建再跑；要求 0 失败
```

- **`scripts/run-tests.sh`** 封装 `xcodebuild test`，专治一个老毛病：带宿主 App 的测试偶尔在结果打印完之后**空转挂住**（0% CPU、永不退出）。它把 xcodebuild 放到后台自成进程组、轮询日志，看到结论行（或收尾行之后静默 20 秒）就收工，**只按自己记下的 PID 回收**（不 pkill）。退出码 0 全绿 / 1 失败或编译错误 / 2 无法判定；末尾会列出本次编译产生的警告。可调项是环境变量，见脚本头注释（`PAWIT_TEST_DESTINATION` 可指到一台关机的模拟器，如 `id=<UDID>`）。
- **查警告要用全新 DerivedData：** 增量构建不会重新编译没改的文件，警告会被藏起来（`ToggleItemIntent.swift:34` 那条只在整包重编译时才出现）。用 `PAWIT_DERIVED_DATA=/tmp/某个新目录 scripts/run-tests.sh`，或 `xcodebuild build-for-testing … -derivedDataPath /tmp/某个新目录`（会连测试 target 一起编译），再 `grep -n 'warning:'` 日志（`run-tests.sh` 末尾本来就会列出）。
- 装进模拟器的 App 在 `<derivedDataPath>/Build/Products/Debug-iphonesimulator/PawIt.app`。

## 3. 往模拟器里放数据 + 临时启动参数补丁

**种数据**（库在 App Group 容器里；先让 App 启动一次把库建好，再 terminate）：

```bash
BID=com.fitpetgo.pawsticky
GROUP=$(xcrun simctl get_app_container <iphone-udid> $BID groups | head -1 | awk -F'\t' '{print $2}')
DB="$GROUP/Library/Application Support/pawit.sqlite3"
sqlite3 "$DB" <<'SQL'
INSERT INTO pet_profile(id,species,displayName,isSelected,acquiredAt) VALUES('cat','cat','Tabby',1,'2026-10-22 08:00:00.000');
INSERT INTO growth_state(petId,fedLevel,streakDays,lastActiveDay,unlockedOutfits) VALUES('cat',0,0,NULL,'[]');
INSERT INTO note(id,text,createdAt,done,dueDate,position,style) VALUES
  ('A1111111-0000-0000-0000-000000000001','Groceries','2026-10-23 08:00:00.000',0,NULL,0,NULL);
INSERT INTO note_item(id,noteId,text,done,position,createdAt) VALUES
  ('B1111111-0000-0000-0000-000000000001','A1111111-0000-0000-0000-000000000001','Milk',1,0,'2026-10-23 08:00:01.000'),
  ('B1111111-0000-0000-0000-000000000002','A1111111-0000-0000-0000-000000000001','Eggs',0,1,'2026-10-23 08:00:02.000');
SQL
```

表与列名以 Core 的迁移为准（上面是 2026-10-23 实测可用的）。往**用户的**库里写之前先问他（§1）。

**临时启动参数补丁（`TEMP-SHOT`）：** 模拟器点不了屏，而 `simctl openurl pawsticky://…` 会弹点不掉的 "Open in …?" 确认框（还会残留到下次重启模拟器）。所以验深链、钉住这类"需要一次点击才能到达"的状态，办法是临时往 `PawItApp.init()` 塞一段读 `ProcessInfo.processInfo.arguments` 的补丁——例如 `-TEMP-SHOT-pin <标题前缀>`（调 `LiveActivityManager` 钉住那条便签；C13 用过）、一个把 URL 交给 `DeepLinkRouter.shared.receive` 的参数（C6 用过，参数名自拟）——然后 `simctl launch <udid> $BID -TEMP-SHOT-pin Groceries`。

**验完必须删：** `git checkout PawIt/PawItApp.swift`，并用 Grep 工具确认源码里没有 `TEMP-SHOT` 残留（别用带通配符的 shell 命令——zsh 会把 `--include=*.swift` 展开，结果不可信）。补丁构建只留在模拟器里，**不要提交、不要上传**。深链验过哪些场景见 `launch-todo.md` 的 C6（配图 `assets/launch-audit/17-widget-deeplink.jpg`）。

## 4. 配对模拟器验 Watch 同步

- 需要一对已配对的 iPhone ↔ Watch 模拟器。
- **必须覆盖两条冷路径：** ① 先有便签、后装手表 App；② iPhone App 没在运行。开发机上 Xcode 同时装两端并重启手表 App 会把它们都掩盖掉（B5 就是这样漏过去的，见 `launch-todo.md` E5）。
- **模拟器假象：** `simctl install` 重装 iPhone App 后，`appconduitd` 会排一次"把内嵌手表 App 自动装到手表上"的任务，约 90 秒后可能失败（`ACXErrorDomain Code=12`）并把手表 App 记成"未安装"，`isWatchAppInstalled` 随之变 false、iPhone 端的推送被守卫跳过——这是两条安装通道记账不一致造成的假象，不是代码问题。对策：原地再 `simctl install` 一次手表 App（这也是验 `sessionWatchStateDidChange` 的现成办法）。
- 看两端日志：`xcrun simctl spawn <udid> log stream --level debug --predicate 'subsystem BEGINSWITH "com.pawit"'`。`log stream` 会遗留孤儿进程——**记下 PID，收工按 PID 清**（禁止 `pkill` / `killall`）。

## 5. 验 Live Activity / 手表智能叠放

- **重装会结束所有 Live Activity**（liveactivitiesd 日志 `Stopping uninstalled activity`）——装完要重新 Pin。
- Activity 复制到手表约 **15–30 秒**（日志 `Adding activity to replicator`）；表盘顶部中间先出现一个小图标，**那还不是卡片**，要在手表上上滑进智能叠放才看得到。过早截图会误以为没出来；Device Hub 里**已经停在旧卡片页的手表窗口不会自己刷新**，要重新上滑。
- App 在**前台**时 Live Activity 的 alert 更新被抑制（不弹横幅、不亮手表），不能拿它来"唤出"卡片。
- iPhone 模拟器截图里**没有灵动岛内容**（只有一个空药丸）。
- **"有没有被系统降级"看日志：** 小呈现里的图片超过系统尺寸上限时不报错，系统静默换成灰色占位圆盘。日志在 iPhone 端 `PawItWidget` 扩展进程里，子系统 `com.apple.chrono`、类别 `archiving`：

```bash
xcrun simctl spawn <iphone-udid> log stream --level debug --predicate 'subsystem == "com.apple.chrono" AND category == "archiving"'
# 事后查：把 stream 换成 show --last 1h --info --debug --style compact
#   [com.apple.chrono:archiving] [3: 144x144] Image permitted                                          ← 正常
#   [com.apple.chrono:archiving] [1: 480x480] Max size exceeded: 437.85x219.6; using placeholder image  ← 被降级成灰圆盘
```

  锁屏 / 横幅 / 展开态里的 480px 图实测是 `Image permitted`；紧凑态 / 最小化 / 手表小卡片只许用 `pet-<sp>-badge`（规则与守卫见 `CLAUDE.md` 代码规范）。

## 6. 版面验证：离屏渲染（ImageRenderer）

模拟器唤不出手表卡片、截不到灵动岛，但 `ImageRenderer` 能把**真实视图**按系统给的画布尺寸渲染成 PNG，用来验排版、截断、颜色、矮画布时丢行。

- 做法：写一个**一次性**的 SwiftUI 工程，放在 `/tmp`（不入库）。要点——
  - `project.yml`（XcodeGen）：依赖本地 `Core` 包；`sources` 里直接引用仓库的 `Shared/NoteActivityAttributes.swift` 与 `PawItWidget/Assets.xcassets`；设 `ASSETCATALOG_COMPILER_APPICON_NAME: ""`（否则报"找不到 AppIcon"）；
  - 视图在 Widget 文件里是 `private`：`run.sh` 用 `sed -E 's/^private (struct|func)/\1/' PawItWidget/NoteActivityLiveActivity.swift > Gen/NoteActivityLiveActivity.swift` 拷一份去掉顶层 `private` 再编译（仓库里的文件不动）；
  - 复用已有的包缓存免联网：`-clonedSourcePackagesDirPath /tmp/pawit-dd/SourcePackages`；
  - App 起来后在 `.task` 里用 `ImageRenderer(content:)`（`scale = 3`），逐个"场景 × 画布"写 PNG 到 `/tmp/snap-out`，最后写一个 `done` 文件并 `exit(0)`；脚本 `simctl install` + `launch` 后轮询 `done`；
  - 渲染出的 PNG 再用 `magick` 裁剪 / 拼图 / 转成 JPG 入库（拼图的注意事项见 §7）。
- 系统给的画布（pt）：手表 40mm 152×69.5 / 41mm 165×72.5 / 42mm 176×72.5 / 44mm 173×76.5 / 45mm 184×80.5 / 46mm 194×80.5 / Ultra 198×81.5；CarPlay 170×78 / 240×78 / 240×100。
- **能证明：** 不溢出、不重叠、该丢的行丢了、截断落在哪、四种便签色下的对比度。**不能证明：** 系统认不认背景色、卡片四周的内边距、点按行为——这些只能在手表上看。
- 为什么不入库：它靠绝对路径和"去掉 private"的 sed 技巧，视图一改名就坏，是会腐烂的脚手架；需要时按上面的要点重建约 10 分钟。

## 7. 截图、日志与收工

- 截图：`xcrun simctl io <udid> screenshot out.png`（iPhone 17 Pro = 1206×2622）；手表同理。裁剪 / 转格式用 `magick`。
- **用 `magick montage` 拼"前后对比"证据图（入库到 `docs/assets/launch-audit/`）有两个坑：** ① 这台机器上找不到 ImageMagick 的默认字体，`montage` 会报错、说明文字画不出来——要显式 `-font /System/Library/Fonts/Supplemental/Arial.ttf`（Arial 只含拉丁字符，所以对比图的标签写英文）；② `-fill` / `-pointsize` / `-background` 这类样式参数要放在图片列表**前面**，放后面不生效。标签太宽会和邻格重叠——先用 `magick -font … -pointsize N label:'…' -format '%w' info:` 量一下最宽标签再定字号。
- **收工清单：** ① `git status` 只有预期的改动；② 用 Grep 确认没有 `TEMP-SHOT`；③ 没有遗留的后台进程（`log stream`、`xcodebuild`）——只按自己记下的 PID 清理；④ 临时文件都在 `/tmp`；⑤ 动过用户的模拟器，就把改了什么告诉他。
