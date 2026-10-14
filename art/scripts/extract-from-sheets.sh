#!/usr/bin/env bash
# 从【已有】角色卡抠出宠物精灵——零生成、零成本、风格与已冻结的 B 风格天然一致。
#
# 为什么不重新生成:gen-images.sh 只支持文生图(请求体里没有参考图字段),
# 重抽同一只宠物会风格漂移,style-notes.md 明确禁止裸提示词重抽。
# 角色卡里的正面图本身就是最好的素材——这个脚本把它抠出来、描边、切胸像。
#
# 用法:
#   art/scripts/extract-from-sheets.sh [输出目录]
#   (默认输出到 art/scripts/.tmp/sheets-out,该目录被 git 忽略)
#
# 输入(按优先级):
#   1. art/scripts/.tmp/raw/<物种>-character-sheet.png   无损母版(git 忽略,只在本机)
#   2. art/characters/<物种>/<物种>-character-sheet.webp 入库版(有损,但足够用)
#   设 FORCE_WEBP=1 可强制只用入库版(= 全新 clone 下会得到的结果)。
#
# 输出(每个物种两张,透明底 + #5B4636 描边,均为原始分辨率,未缩放):
#   <物种>-full.png   完整正面图(耳朵到脚)——欢迎页英雄位 / 选宠卡片
#   <物种>-bust.png   头 + 上胸(耳朵完整)——头像 / 圆形裁切 / Widget 角标 / Watch
#
# 依赖: ImageMagick 7(magick)、awk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="$ROOT/art/scripts/.tmp/raw"
SHEETS="$ROOT/art/characters"
OUT="${1:-$ROOT/art/scripts/.tmp/sheets-out}"

SPECIES=(cat graycat corgi shiba rabbit hamster)
SHEET_W=1536   # 角色卡 16:9,1536x864
SHEET_H=864

# 胸像 = 完整图顶部多少百分比。目测定的:兔子耳朵长,要到 72% 才把脸包进来;柴犬/柯基脸大,56–57% 就够。
bust_percent() {
  case "$1" in
    cat) echo 64 ;; graycat) echo 69 ;; corgi) echo 57 ;;
    shiba) echo 56 ;; rabbit) echo 72 ;; hamster) echo 72 ;;
    *) echo "未知物种: $1" >&2; return 1 ;;
  esac
}

# 胸像里被"硬切"后留下的游离碎片:只有灰猫有——尾巴尖在胸像右下角露出一小块白色。
# 格式 x0,y0 x1,y1(胸像坐标系,把这块矩形抹成透明)。身体最右到 x≈311、尾巴尖从 x≈350 起,留了 ~20px 余量;
# 抹完后脚本会校验"胸像只剩一个连通块",以后换了角色卡会立刻报错而不是悄悄出残图。
bust_erase_rect() {
  case "$1" in
    graycat) echo "330,330 430,430" ;;
    *) echo "" ;;
  esac
}

# 连通块个数(面积 ≥ 40px 才算,忽略抗锯齿碎屑)
component_count() {
  magick "$1" -alpha extract -threshold 50% \
    -define connected-components:area-threshold=40 \
    -define connected-components:verbose=true \
    -connected-components 8 null: 2>&1 | awk 'NR > 1 && /gray\(255\)|srgb\(255,255,255\)|white/ { c++ } END { print c + 0 }'
}

command -v magick >/dev/null || { echo "缺少 ImageMagick(brew install imagemagick)" >&2; exit 1; }
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for sp in "${SPECIES[@]}"; do
  src="$RAW/$sp-character-sheet.png"
  if [[ -n "${FORCE_WEBP:-}" || ! -f "$src" ]]; then
    src="$SHEETS/$sp/$sp-character-sheet.webp"
  fi
  [[ -f "$src" ]] || { echo "找不到 $sp 的角色卡" >&2; exit 1; }

  # 1) 从四周泛洪去底。背景是 253–255 的近白噪声;白毛最接近背景的也有 ~4%
  #    (graycat ≈ (247,244,241)、rabbit ≈ (244,241,236)),所以 fuzz 只能取 2%——
  #    取 8% 会把白毛一起吃掉。
  magick "$src" -alpha set -bordercolor "rgb(254,254,254)" -border 1 \
    -fuzz 2% -fill none -draw "color 0,0 floodfill" -shave 1x1 +repage "$WORK/$sp-alpha.png"

  # 2) 角色卡是 正面 / 侧面 / 背面 三视图并排,视图之间至少有 12px 全透明列。
  #    把 alpha 压成 1 像素高,找最左边那一段连续非空列 = 正面图。
  read -r xs xe < <(
    magick "$WORK/$sp-alpha.png" -alpha extract -scale "${SHEET_W}x1!" -threshold 0 txt:- |
      awk -F'[,: ]+' 'NR > 1 {
        x = $1; v = ($4 > 0) ? 1 : 0
        if (v && !inrun && !done) { inrun = 1; xs = x }
        if (inrun) {
          if (v) { last = x; gap = 0 }
          else { gap++; if (gap >= 12) { print xs, last; done = 1; inrun = 0; exit } }
        }
      }
      END { if (!done && inrun) print xs, last }'
  )
  [[ -n "${xs:-}" && -n "${xe:-}" ]] || { echo "$sp: 没找到正面图的列范围" >&2; exit 1; }
  w=$((xe - xs + 1))

  # 3) 裁出正面图 → 修边 → 腐蚀 1px(去掉泛洪留下的白边)→ 加描边。
  #    style-notes 的描边是 1024px 图上 disk:3;这里完整图约 600px 高,按比例取 disk:2。
  magick "$WORK/$sp-alpha.png" -crop "${w}x${SHEET_H}+${xs}+0" +repage -trim +repage \
    -channel A -morphology erode disk:1 +channel \
    \( +clone -alpha extract -morphology dilate disk:2 -background "#5B4636" -alpha shape \) \
    -compose DstOver -composite -depth 8 "$OUT/$sp-full.png"

  # 4) 胸像:取完整图顶部若干百分比,底边硬切(用作圆形头像时底边本来就被裁掉)。
  fw=$(magick identify -format %w "$OUT/$sp-full.png")
  fh=$(magick identify -format %h "$OUT/$sp-full.png")
  pct=$(bust_percent "$sp")
  bh=$((fh * pct / 100))
  magick "$OUT/$sp-full.png" -crop "${fw}x${bh}+0+0" +repage "$OUT/$sp-bust.png"
  rect=$(bust_erase_rect "$sp")
  if [[ -n "$rect" ]]; then
    # 经典 IM 写法:把 alpha 抽成灰度图 → 在上面涂黑矩形 → 再当 alpha 贴回去
    # (-region + -alpha transparent、-compose Clear + -draw 在 IM7 里都不可靠,实测过)
    magick "$OUT/$sp-bust.png" \( +clone -alpha extract -fill black -draw "rectangle $rect" \) \
      -alpha off -compose CopyOpacity -composite "$OUT/$sp-bust.png"
  fi

  # 5) 自检:完整图与胸像都必须是单一连通块(没有残留的背景碎屑或被切断的肢体)。
  for kind in full bust; do
    n=$(component_count "$OUT/$sp-$kind.png")
    [[ "$n" == "1" ]] || { echo "$sp-$kind 有 $n 个连通块,应为 1——检查泛洪 fuzz 或胸像比例" >&2; exit 1; }
  done

  printf '%-8s 正面列 %4s..%-4s  full %4sx%-4s  bust %4sx%-4s (%s%%)  ← %s\n' \
    "$sp" "$xs" "$xe" "$fw" "$fh" "$fw" "$bh" "$pct" "$(basename "$src")"
done

echo "完成 → $OUT"
