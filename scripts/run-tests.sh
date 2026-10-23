#!/bin/bash
# 跑 `xcodebuild test`，并绕开一个老毛病：带宿主 App 的测试偶尔在结果打印完之后空转挂住
# （0% CPU、永不退出），人不盯着就一直卡在那。
#
# 用法：
#   scripts/run-tests.sh                                         # 全量（Core + App）
#   scripts/run-tests.sh -only-testing:PawItTests/PawItTests     # 其余参数原样交给 xcodebuild
#
# 环境变量（都可选）：
#   PAWIT_TEST_DESTINATION   目的地；默认 'platform=iOS Simulator,name=iPhone 17 Pro'
#                            （想避开正在用的模拟器，就传一台关机的：'id=<UDID>'）
#   PAWIT_DERIVED_DATA       传给 -derivedDataPath；默认用 Xcode 自己的位置。
#                            想看警告的全貌就给一个全新目录——增量构建不会重新编译没改的文件，警告会被藏起来
#   PAWIT_TEST_LOG           完整日志路径；默认 /tmp/pawit-test.log
#   RUN_TESTS_QUIET_SECONDS  测试收尾行出现后静默多久算“挂住”；默认 20
#   RUN_TESTS_MAX_SECONDS    整体超时；默认 1500
#
# 做法：xcodebuild 放到后台自成进程组 → 轮询日志 → 出现 xcodebuild 自己的结论行（先给它 10 秒自己退出），
# 或 Swift Testing 的收尾行之后静默超时，就收工 → 退不出来的，只按自己记下的 PID 回收（绝不 pkill / killall：
# 用户自己的终端里可能跑着同样的程序），并在摘要里注明“回收过”。
#
# 退出码：0 全绿 · 1 有失败 / 编译错误 · 2 无法判定（超时、或没有任何测试结果）。
# 末尾会列出本次编译产生的警告（只是列出，不影响退出码）。

set -u
cd "$(dirname "$0")/.." || exit 2

LOG="${PAWIT_TEST_LOG:-/tmp/pawit-test.log}"
QUIET="${RUN_TESTS_QUIET_SECONDS:-20}"
MAX="${RUN_TESTS_MAX_SECONDS:-1500}"

# 调用方没指定的才补默认值（重复传 -destination 会让 xcodebuild 对两个目的地各跑一遍）
args=(test)
[[ " $* " == *" -project "* ]]     || args+=(-project PawIt.xcodeproj)
[[ " $* " == *" -scheme "* ]]      || args+=(-scheme PawIt)
[[ " $* " == *" -destination "* ]] || args+=(-destination "${PAWIT_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}")
[ -n "${PAWIT_DERIVED_DATA:-}" ] && args+=(-derivedDataPath "$PAWIT_DERIVED_DATA")
args+=("$@")

set -m                       # 让后台任务自成进程组，便于整组回收
xcodebuild "${args[@]}" > "$LOG" 2>&1 &
PID=$!
set +m                       # 进程组已经建好；之后的管道不需要作业控制（留着会让 bash 打印 "child setpgid" 噪音）
START=$(date +%s)

while kill -0 "$PID" 2>/dev/null; do
  # 终止标记之一：xcodebuild 自己的结论行。先给它 10 秒自己退出；退不出来才是那个“挂住”的老毛病
  if grep -qE '^\*\* (TEST|BUILD) (SUCCEEDED|FAILED) \*\*' "$LOG"; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
    break
  fi
  # 终止标记之二：swift-testing 的收尾行出现后又静默了 QUIET 秒（= 挂住）
  if grep -qE '^(✔|✘) Test run with' "$LOG"; then
    LAST=$(stat -f %m "$LOG"); NOW=$(date +%s)
    if (( NOW - LAST > QUIET )); then break; fi
  fi
  if (( $(date +%s) - START > MAX )); then echo "TIMEOUT after ${MAX}s"; break; fi
  sleep 2
done

# 只按自己记下的 PID（进程组）回收。整段包进 { } 2>/dev/null：
# bash 会在进程被信号结束后异步打印 “Terminated: 15 …” 的作业通知，只给 wait 加重定向压不住它。
REAPED=""
if kill -0 "$PID" 2>/dev/null; then
  REAPED=1
  { kill -TERM -- "-$PID"; sleep 2; kill -KILL -- "-$PID"; } 2>/dev/null
fi
{ wait "$PID"; } 2>/dev/null

echo "--- build errors ---"
grep -E '(^|: )error: ' "$LOG" | sort -u | cut -c1-220 | head -20
echo "--- failed tests ---"
grep -E '^✘ Test [a-zA-Z]' "$LOG" | cut -c1-200 | head -20
echo "--- warnings (this run's compile only) ---"
WARNINGS=$(grep -E '^/.+:[0-9]+:[0-9]+: warning: ' "$LOG" | sed -E 's/ \[#[A-Za-z]+\]$//' | sort -u)
if [ -n "$WARNINGS" ]; then printf '%s\n' "$WARNINGS" | cut -c1-220; else echo "(none)"; fi
echo "--- summary ---"
grep -E '^(✔|✘) Test run with|^\*\* (TEST|BUILD)' "$LOG" | cut -c1-200
[ -n "$REAPED" ] && echo "note: xcodebuild 出结论后没有自己退出，已按它的进程组回收（即上面说的挂住问题；结果以上面的行为准）"
echo "log: $LOG"

if grep -qE '^\*\* (TEST|BUILD) FAILED \*\*|^✘ Test run with|(^|: )error: ' "$LOG"; then exit 1; fi
if grep -qE '^\*\* TEST SUCCEEDED \*\*' "$LOG"; then exit 0; fi
if grep -qE '^✔ Test run with' "$LOG"; then exit 0; fi   # 挂住被回收，但结果已全绿
exit 2
