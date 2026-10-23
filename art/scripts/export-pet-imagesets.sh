#!/usr/bin/env bash
# 把 extract-from-sheets.sh 抠出的精灵导出成 App 用的 imageset(零生成)。
#
#   pet-<sp>-front  胸像。方形画布,胸像按 88% 内接框居中(@1x/2x/3x = 100/200/300px)。
#                   写入 PawIt / PawItWidget / PawItWatch / PawItWatchWidget 四个 catalog。
#   pet-<sp>-full   全身。不加边距,按高度缩放(@1x/2x/3x = 200/400/600px 高)。
#                   只写入 PawIt,且只导出 FULL_SPECIES 里的物种:目前只有欢迎页英雄位用(固定是 cat,
#                   那时用户还没选宠)。选宠卡用胸像更好——90pt 的位置上全身图脸太小(2026-10-14 实测)。
#                   以后哪里需要别的物种的全身图,把它加进 FULL_SPECIES 再跑一遍即可。
#   pet-<sp>-badge  Live Activity「小呈现」专用头像:同一张胸像、同样的 88% 内接框,但只有 48/96/144px。
#                   只写入 PawItWidget。**不能用 front/holding 代替**——系统归档 Live Activity 画面时
#                   会按呈现形式的尺寸卡图片上限,超限就静默换成灰色占位图(日志:
#                   "Max size exceeded: 437.85x219.6; using placeholder image";2026-10-23 在 Watch 智能
#                   叠放上实测:480px 的 holding 图被换成了灰圆盘。300px 的 front 是否也越界没有验证,
#                   所以按保守口径:紧凑 / 小呈现一律只用这个 ≤144px 的档位)。
#                   上限由 scripts/preflight.sh 守住(BADGE_MAX_PX)。
#
# 用法:
#   art/scripts/extract-from-sheets.sh            # 先抠图 → art/scripts/.tmp/sheets-out
#   art/scripts/export-pet-imagesets.sh [抠图目录]   # 再导出(默认 art/scripts/.tmp/sheets-out)
#
# 名字沿用 pet-<sp>-front,所以 ~20 处引用(头像 / 锁屏 / Watch / 分享卡 / Live Activity)零改动。
# cat / corgi 的 holding、happy 图不动(Widget 角落的举牌小图仍用它们)。
# 依赖:ImageMagick 7(magick)。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:-$ROOT/art/scripts/.tmp/sheets-out}"
SPECIES=(cat graycat corgi shiba rabbit hamster)
FRONT_CATALOGS=(PawIt PawItWidget PawItWatch PawItWatchWidget)
FULL_CATALOGS=(PawIt)
FULL_SPECIES=(cat)
BADGE_CATALOGS=(PawItWidget)

FRONT_BOX_PERCENT=88   # 胸像占方形画布的比例;PetAvatarView 再按 0.85 画进圆里,所以耳尖不会出圈
FRONT_BASE=100         # @1x 画布边长(px)
FULL_BASE_HEIGHT=200   # @1x 全身高度(px)
BADGE_BASE=48          # Live Activity 小头像 @1x 边长(px)→ 48/96/144;@3x 的 144px 远低于系统上限

for sp in "${SPECIES[@]}"; do
  for kind in bust full; do
    [[ -f "$SRC/$sp-$kind.png" ]] || { echo "缺 $SRC/$sp-$kind.png——先跑 art/scripts/extract-from-sheets.sh" >&2; exit 1; }
  done
done

# 写 Contents.json(三档 scale)
write_contents() {  # 目录 名字
  cat > "$1/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$2@1x.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "$2@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "$2@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
}

# 胸像 → 方形画布(PNG32 强制保留 RGBA,避免 IM 自动量化成 256 色调色板导致偏色)
export_square() {  # 源 目录 名字 @1x边长
  local scale canvas box
  for scale in 1 2 3; do
    canvas=$(($4 * scale))
    box=$((canvas * FRONT_BOX_PERCENT / 100))
    magick "$1" -background none -alpha set -filter Lanczos -resize "${box}x${box}" \
      -gravity center -extent "${canvas}x${canvas}" -depth 8 -strip "PNG32:$2/$3@${scale}x.png"
  done
}
export_front() { export_square "$1" "$2" "$3" "$FRONT_BASE"; }   # 源 目录 名字
export_badge() { export_square "$1" "$2" "$3" "$BADGE_BASE"; }   # 源 目录 名字

# 全身 → 按高度缩放,保持原宽高比
export_full() {  # 源 目录 名字
  local scale height
  for scale in 1 2 3; do
    height=$((FULL_BASE_HEIGHT * scale))
    magick "$1" -background none -alpha set -filter Lanczos -resize "x${height}" \
      -depth 8 -strip "PNG32:$2/$3@${scale}x.png"
  done
}

for sp in "${SPECIES[@]}"; do
  for catalog in "${FRONT_CATALOGS[@]}"; do
    dir="$ROOT/$catalog/Assets.xcassets/pet-$sp-front.imageset"
    mkdir -p "$dir"
    export_front "$SRC/$sp-bust.png" "$dir" "pet-$sp-front"
    write_contents "$dir" "pet-$sp-front"
  done
  for catalog in "${BADGE_CATALOGS[@]}"; do
    dir="$ROOT/$catalog/Assets.xcassets/pet-$sp-badge.imageset"
    mkdir -p "$dir"
    export_badge "$SRC/$sp-bust.png" "$dir" "pet-$sp-badge"
    write_contents "$dir" "pet-$sp-badge"
  done
  full_note=""
  for fs in "${FULL_SPECIES[@]}"; do
    if [[ "$fs" == "$sp" ]]; then
      for catalog in "${FULL_CATALOGS[@]}"; do
        dir="$ROOT/$catalog/Assets.xcassets/pet-$sp-full.imageset"
        mkdir -p "$dir"
        export_full "$SRC/$sp-full.png" "$dir" "pet-$sp-full"
        write_contents "$dir" "pet-$sp-full"
      done
      full_note=",full × ${#FULL_CATALOGS[@]} 个 catalog"
    fi
  done
  echo "$sp:front × ${#FRONT_CATALOGS[@]} 个 catalog,badge × ${#BADGE_CATALOGS[@]} 个 catalog$full_note"
done
echo "完成。接着跑 scripts/preflight.sh 检查素材齐全。"
