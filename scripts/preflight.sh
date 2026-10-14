#!/usr/bin/env bash
# 上线前置检查（preflight）：把 docs/launch-readiness.md 的 P0 配置项变成可执行断言。
#
# 用法：scripts/preflight.sh [path/to/PawIt.app]
#   先构建：xcodegen generate && xcodebuild -project PawIt.xcodeproj -scheme PawIt \
#           -destination 'generic/platform=iOS Simulator' build
#   （不要加 -sdk iphonesimulator：它会把 watchOS target 也按 iOS SDK 编译而失败。）
#   不带参数时用 xcodebuild -showBuildSettings 推断产物路径（Debug-iphonesimulator）。
#
# 退出码：0 = 没有 ❌（可能还有 ⏳：依赖外部输入，如图标 / Team ID）；1 = 存在 ❌。
# 只依赖 bash 3.2 / grep / plutil / sips，可直接在终端运行（不依赖 rg）。
set -uo pipefail
cd "$(dirname "$0")/.."

EXPECTED_ID="com.fitpetgo.pawsticky"
EXPECTED_GROUP="group.com.fitpetgo.pawsticky.shared"
EXPECTED_NAME="PawSticky"

pass=0; pend=0; fail=0
ok()   { printf '  ✅ %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  ❌ %s\n' "$1"; fail=$((fail + 1)); }
pending() { printf '  ⏳ %s\n' "$1"; pend=$((pend + 1)); }
section() { printf '\n== %s\n' "$1"; }

# plist <file> <key> → 打印值；缺键时返回非零（布尔值打印 true/false）
plist() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# eq <描述> <实际值> <期望值>
eq() {
  if [[ "$2" == "$3" ]]; then ok "$1 = $3"; else bad "$1：期望 '$3'，实际 '${2:-<缺失>}'"; fi
}

# ---------------------------------------------------------------------------
section "源码：App Group 与品牌字符串"

group_const=$(grep -E 'appGroupID *= *"' Core/Sources/Core/Core.swift | sed -E 's/.*"([^"]+)".*/\1/')
eq "PawItInfo.appGroupID" "$group_const" "$EXPECTED_GROUP"
for ent in PawIt/PawIt.entitlements PawItWidget/PawItWidget.entitlements \
           PawItWatch/PawItWatch.entitlements PawItWatchWidget/PawItWatchWidget.entitlements; do
  if grep -q "<string>$EXPECTED_GROUP</string>" "$ent"; then
    ok "$ent 含 $EXPECTED_GROUP"
  else
    bad "$ent 未包含 $EXPECTED_GROUP"
  fi
done

# 用户可见的旧品牌名：字符串字面量里出现独立的 PawIt（PawItWidget / PawItDeepLink 等内部标识不算）
leftover=$(grep -rnE --include='*.swift' --exclude-dir=.build \
  '"[^"]*PawIt([^A-Za-z0-9_"][^"]*)?"' Core PawIt PawItWidget PawItWatch PawItWatchWidget Shared PawItTests 2>/dev/null)
if [[ -z "$leftover" ]]; then
  ok "Swift 字符串字面量中没有残留的旧品牌名 PawIt"
else
  bad "仍有字符串字面量含旧品牌名 PawIt："
  printf '%s\n' "$leftover" | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
section "源码：生成的 Info.plist（Info.plist 由 XcodeGen 生成，改 project.yml）"

for target in PawIt PawItWidget PawItWatch PawItWatchWidget; do
  eq "$target 版本号取自 MARKETING_VERSION" \
     "$(plist "$target/Info.plist" CFBundleShortVersionString)" '$(MARKETING_VERSION)'
  eq "$target 构建号取自 CURRENT_PROJECT_VERSION" \
     "$(plist "$target/Info.plist" CFBundleVersion)" '$(CURRENT_PROJECT_VERSION)'
done

# 相册 API 的调用（排除注释行）：没有用途描述字符串时，运行期访问会直接终止进程
photos_use=$(grep -rnE --include='*.swift' --exclude-dir=.build \
  'UIImageWriteToSavedPhotosAlbum|PHPhotoLibrary|PHAssetCreationRequest' \
  Core PawIt PawItWidget PawItWatch PawItWatchWidget Shared 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')
if [[ -n "$photos_use" ]]; then
  if plist PawIt/Info.plist NSPhotoLibraryAddUsageDescription >/dev/null; then
    ok "使用了相册 API，且声明了 NSPhotoLibraryAddUsageDescription"
  else
    bad "代码直接调用相册 API，但 Info.plist 缺 NSPhotoLibraryAddUsageDescription（运行时会崩溃）"
  fi
else
  ok "没有直接访问相册的代码（保存走系统分享面板）"
fi

# ---------------------------------------------------------------------------
section "构建产物"

BS=$(xcodebuild -project PawIt.xcodeproj -scheme PawIt -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null)
APP="${1:-}"
if [[ -z "$APP" && -z "$BS" ]]; then
  bad "xcodebuild -showBuildSettings 没有输出（先 xcodegen generate，或直接传入 .app 路径）"
elif [[ -z "$APP" ]]; then
  dir=$(printf '%s\n' "$BS" | awk -F' = ' '/^ *TARGET_BUILD_DIR = /{print $2; exit}')
  name=$(printf '%s\n' "$BS" | awk -F' = ' '/^ *FULL_PRODUCT_NAME = /{print $2; exit}')
  APP="$dir/$name"
fi
WIDGET="$APP/PlugIns/PawItWidget.appex"
WATCH="$APP/Watch/PawItWatch.app"
WATCH_WIDGET="$WATCH/PlugIns/PawItWatchWidget.appex"

if [[ ! -d "$APP" || ! -d "$WIDGET" || ! -d "$WATCH" || ! -d "$WATCH_WIDGET" ]]; then
  bad "找不到完整的构建产物（${APP}）——先构建再跑 preflight"
else
  ok "构建产物：$APP"

  section "标识与名称"
  eq "iOS App bundle id"      "$(plist "$APP/Info.plist" CFBundleIdentifier)"          "$EXPECTED_ID"
  eq "Widget bundle id"       "$(plist "$WIDGET/Info.plist" CFBundleIdentifier)"       "$EXPECTED_ID.widgets"
  eq "Watch App bundle id"    "$(plist "$WATCH/Info.plist" CFBundleIdentifier)"        "$EXPECTED_ID.watchkitapp"
  eq "Watch Widget bundle id" "$(plist "$WATCH_WIDGET/Info.plist" CFBundleIdentifier)" "$EXPECTED_ID.watchkitapp.widgets"
  eq "Watch 伴侣 App id"      "$(plist "$WATCH/Info.plist" WKCompanionAppBundleIdentifier)" "$EXPECTED_ID"
  eq "iOS App 显示名"         "$(plist "$APP/Info.plist" CFBundleDisplayName)"   "$EXPECTED_NAME"
  eq "Watch App 显示名"       "$(plist "$WATCH/Info.plist" CFBundleDisplayName)" "$EXPECTED_NAME"
  eq "Widget 显示名"          "$(plist "$WIDGET/Info.plist" CFBundleDisplayName)"       "$EXPECTED_NAME Widget"
  eq "Watch Widget 显示名"    "$(plist "$WATCH_WIDGET/Info.plist" CFBundleDisplayName)" "$EXPECTED_NAME Widget"

  section "版本号（四个 bundle 必须一致，且等于 project.yml）"
  want_ver=$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)
  want_build=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/{print $2; exit}' project.yml)
  for b in "$APP" "$WIDGET" "$WATCH" "$WATCH_WIDGET"; do
    label=$(basename "$b")
    eq "$label 版本号" "$(plist "$b/Info.plist" CFBundleShortVersionString)" "$want_ver"
    eq "$label 构建号" "$(plist "$b/Info.plist" CFBundleVersion)" "$want_build"
  done

  section "隐私清单（PrivacyInfo.xcprivacy）"
  for b in "$APP" "$WIDGET" "$WATCH" "$WATCH_WIDGET"; do
    label=$(basename "$b"); m="$b/PrivacyInfo.xcprivacy"
    if [[ ! -f "$m" ]]; then
      bad "$label 缺 PrivacyInfo.xcprivacy"
    elif ! plutil -lint "$m" >/dev/null 2>&1; then
      bad "$label 的 PrivacyInfo.xcprivacy 不是合法 plist"
    else
      eq "$label NSPrivacyTracking" "$(plist "$m" NSPrivacyTracking)" "false"
    fi
  done

  section "外观与合规"
  eq "iOS App 锁定浅色外观（UIUserInterfaceStyle）" "$(plist "$APP/Info.plist" UIUserInterfaceStyle)" "Light"
  if plist "$APP/Info.plist" ITSAppUsesNonExemptEncryption >/dev/null; then
    ok "ITSAppUsesNonExemptEncryption = $(plist "$APP/Info.plist" ITSAppUsesNonExemptEncryption)（合规声明，需公司确认）"
  else
    bad "缺 ITSAppUsesNonExemptEncryption（每次上传都会弹出口合规问卷）"
  fi
  eq "iOS App 设备族（仅 iPhone）" "$(plutil -extract UIDeviceFamily json -o - "$APP/Info.plist" 2>/dev/null)" "[1]"
  eq "Widget 设备族（仅 iPhone）"  "$(plutil -extract UIDeviceFamily json -o - "$WIDGET/Info.plist" 2>/dev/null)" "[1]"
fi

# ---------------------------------------------------------------------------
section "依赖外部输入的项（⏳ 不算失败）"

team=$(printf '%s\n' "$BS" | awk -F' = ' '/^ *DEVELOPMENT_TEAM = /{print $2; exit}')
if [[ -n "${team// /}" ]]; then
  ok "DEVELOPMENT_TEAM = $team"
else
  pending "DEVELOPMENT_TEAM 未设置——创建 Config/Signing.local.xcconfig（见 .example）后才能真机 / Archive"
fi

for icon_dir in PawIt/Assets.xcassets/AppIcon.appiconset PawItWatch/Assets.xcassets/AppIcon.appiconset; do
  png=$(ls "$icon_dir"/*.png 2>/dev/null | head -1)
  if [[ -z "$png" ]]; then
    pending "$icon_dir 没有图标 PNG（见 docs/launch-todo.md 的 A4 / C2）"
  else
    w=$(sips -g pixelWidth "$png" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$png" | awk '/pixelHeight/{print $2}')
    a=$(sips -g hasAlpha "$png" | awk '/hasAlpha/{print $2}')
    if [[ "$w" == "1024" && "$h" == "1024" && "$a" == "no" ]]; then
      ok "${icon_dir}：1024×1024 且无 alpha"
    else
      bad "${icon_dir}：图标须为 1024×1024 且无 alpha（实际 ${w}×${h}，hasAlpha=${a}）"
    fi
  fi
done

# ---------------------------------------------------------------------------
printf '\n结果：%d 通过 · %d 等待外部输入 · %d 失败\n' "$pass" "$pend" "$fail"
[[ $fail -eq 0 ]]
