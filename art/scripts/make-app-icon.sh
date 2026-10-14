#!/usr/bin/env bash
# 零生成 App 图标:用已有的举牌猫 B_cat-sitting 合成 1024×1024 sRGB 8-bit 无 alpha PNG,
# 同时写入 iOS 与 watchOS 的 AppIcon.appiconset(watchOS 系统会套圆形遮罩,猫完全落在圆内)。
#
# 用法:art/scripts/make-app-icon.sh [输出目录]
#   不带参数:写入 PawIt/ 与 PawItWatch/ 的 AppIcon.appiconset(文件名 AppIcon-1024.png)。
#   带输出目录:只写 <目录>/AppIcon-1024.png,不动工程(用来试色)。
# 环境变量:
#   ICON_TOP / ICON_BOTTOM  渐变上 / 下色(默认 A4 选定的天蓝 #D4E9FF → #9CCBF5)
#   FORCE_WEBP=1            强制用仓库内的有损 webp 作源(默认优先用无损母版 .tmp/raw/*.png)
#
# 依赖:ImageMagick 7(magick)。抠图配方与 docs/launch-art-prompts.md §0.5 的 process_sprite 相同;
# B_cat-sitting 是饱和色图,fuzz 8% 安全(白毛角色不可用 8%,见同文档警告)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="$ROOT/art/scripts/.tmp/raw/B_cat-sitting.png"
WEBP="$ROOT/art/style-pack/frozen/B_cat-sitting.webp"
TOP="${ICON_TOP:-#D4E9FF}"
BOTTOM="${ICON_BOTTOM:-#9CCBF5}"

if [[ -f "$RAW" && -z "${FORCE_WEBP:-}" ]]; then SRC="$RAW"; else SRC="$WEBP"; fi
[[ -f "$SRC" ]] || { echo "找不到源图 $SRC" >&2; exit 1; }
echo "源图:${SRC#"$ROOT"/}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1) 抠图(四周加 1px 近白边再 flood-fill,避免被图内白色截断)+ 腐蚀 1px + 3px 描边 #5B4636
magick "$SRC" -alpha set -bordercolor "rgb(254,254,254)" -border 1 \
  -fuzz 8% -fill none -draw "color 0,0 floodfill" -shave 1x1 +repage \
  -channel A -morphology erode disk:1 +channel \
  \( +clone -alpha extract -morphology dilate disk:3 -background "#5B4636" -alpha shape \) \
  -compose DstOver -composite -depth 8 "$WORK/sprite.png"

# 2) 渐变底 + 居中(猫高 760px,略微下移 10px 视觉居中)→ 去 alpha、去元数据
magick -size 1024x1024 "gradient:${TOP}-${BOTTOM}" \
  \( "$WORK/sprite.png" -trim +repage -resize x760 \) \
  -gravity center -geometry +0+10 -composite \
  -colorspace sRGB -alpha off -depth 8 -strip "$WORK/AppIcon-1024.png"

# 3) 自检:尺寸 / 无 alpha
w=$(magick identify -format '%w' "$WORK/AppIcon-1024.png")
h=$(magick identify -format '%h' "$WORK/AppIcon-1024.png")
ch=$(magick identify -format '%[channels]' "$WORK/AppIcon-1024.png")
if [[ "$w" != "1024" || "$h" != "1024" || "$ch" == *a ]]; then
  echo "自检失败:${w}×${h} channels=${ch}(要求 1024×1024 且无 alpha)" >&2
  exit 1
fi

# 4) 输出
if [[ $# -ge 1 ]]; then
  mkdir -p "$1"
  cp "$WORK/AppIcon-1024.png" "$1/AppIcon-1024.png"
  echo "已写入 $1/AppIcon-1024.png"
else
  for set in PawIt PawItWatch; do
    dest="$ROOT/$set/Assets.xcassets/AppIcon.appiconset"
    cp "$WORK/AppIcon-1024.png" "$dest/AppIcon-1024.png"
    echo "已写入 ${dest#"$ROOT"/}/AppIcon-1024.png"
  done
  echo "提醒:Contents.json 的 images[0] 需带 \"filename\" : \"AppIcon-1024.png\"(preflight 会检查)。"
fi
