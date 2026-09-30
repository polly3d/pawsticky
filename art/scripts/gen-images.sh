#!/usr/bin/env bash
# PawIt 美术生成管线(适配自 tryon/scripts/gen-images.sh)
# 用法: ./gen-images.sh test candidates a-cat-sitting   # 单张试生成
#       ./gen-images.sh batch candidates                # 生成整个类别
#       ./gen-images.sh list [category]                 # 列出 prompts
# 类别: candidates(风格候选 12 张) / characters(角色卡,风格冻结后填充)
# Key: art/scripts/.env.gen 或回退借用 ~/Project/ai/tryon/scripts/.env.gen
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # PawIt 项目根
PROMPTS_DIR="$SCRIPT_DIR/prompts"
TMP_DIR="$SCRIPT_DIR/.tmp"
RAW_DIR="$TMP_DIR/raw"
FAILED_LOG="$SCRIPT_DIR/failed.log"

DEFAULT_MODEL="openai/gpt-image-2.5-flare"
API_URL="https://openrouter.ai/api/v1/images"
DELAY=2
CATEGORIES="candidates characters"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; NC='\033[0m'

usage() { cat <<EOF
${BOLD}PawIt Image Generator${NC}
Usage:
  $0 test  <category> <id>    单张生成(先试它!)
  $0 batch <category>         生成整个类别
  $0 list  [category]         列出可用 prompts
Categories: ${CATEGORIES}
Options: --model <slug>  默认 ${DEFAULT_MODEL}
         --force         覆盖已存在文件
         --delay <sec>   API 调用间隔(默认 ${DELAY}s)
Env: OPENROUTER_API_KEY(或 art/scripts/.env.gen,回退 tryon/scripts/.env.gen)
EOF
exit 0; }

check_deps() {
  local missing=()
  for cmd in curl jq magick cwebp; do command -v "$cmd" &>/dev/null || missing+=("$cmd"); done
  if [[ ${#missing[@]} -gt 0 ]]; then echo -e "${RED}Missing: ${missing[*]}${NC} (brew install imagemagick webp jq)"; exit 1; fi
}

check_api_key() {
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    for f in "$SCRIPT_DIR/.env.gen" "$HOME/Project/ai/tryon/scripts/.env.gen"; do
      [[ -f "$f" ]] && source "$f" && break
    done
  fi
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then echo -e "${RED}OPENROUTER_API_KEY not set${NC}"; exit 1; fi
}

decode_b64() { [[ "$(uname)" == "Darwin" ]] && base64 -D || base64 -d; }

generate_one() {
  local id="$1" prompt="$2" aspect_ratio="$3" resize="$4" output_dir="$5" filename="$6"
  local full_dir="$ROOT_DIR/$output_dir"
  local output_path="$full_dir/$filename.webp"
  if [[ -f "$output_path" && "$FORCE" == false ]]; then echo -e "  ${YELLOW}⏭  $filename.webp 已存在(--force 覆盖)${NC}"; return 0; fi
  mkdir -p "$RAW_DIR" "$full_dir"
  local resp_file="$TMP_DIR/${filename}_resp.json" raw_file="$RAW_DIR/$filename.png" resized="$TMP_DIR/${filename}_resized.png" cost="cached"
  if [[ -s "$raw_file" && "$FORCE" == false ]]; then
    echo -ne "  ♻️  $filename — raw 缓存,仅转换..."
  else
    echo -ne "  ⏳ $filename — 调用 API..."
    local http_code
    http_code=$(curl -s -o "$resp_file" -w "%{http_code}" --max-time 180 "$API_URL" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" -H "Content-Type: application/json" \
      -d "$(jq -n --arg model "$MODEL" --arg prompt "$prompt" --arg ar "$aspect_ratio" \
        '{model: $model, prompt: $prompt, aspect_ratio: $ar, quality: "high", n: 1}')")
    if [[ "$http_code" != "200" ]]; then
      local err; err=$(jq -r '.error.message // .error // "unknown"' "$resp_file" 2>/dev/null || echo "HTTP $http_code")
      echo -e "\r  ${RED}✗ $filename${NC} — HTTP $http_code: $err"
      echo "$(date '+%F %T') | $id | HTTP $http_code | $err" >> "$FAILED_LOG"; rm -f "$resp_file"; return 1
    fi
    local b64; b64=$(jq -r '.data[0].b64_json // empty' "$resp_file")
    if [[ -n "$b64" ]]; then echo "$b64" | decode_b64 > "$raw_file"
    else
      local url; url=$(jq -r '.data[0].url // empty' "$resp_file")
      if [[ -n "$url" ]]; then curl -s --max-time 60 -o "$raw_file" "$url"
      else echo -e "\r  ${RED}✗ $filename — 响应无图像数据${NC}"; echo "$(date '+%F %T') | $id | no image data" >> "$FAILED_LOG"; rm -f "$resp_file"; return 1; fi
    fi
    [[ -s "$raw_file" ]] || { echo -e "\r  ${RED}✗ $filename — 解码为空${NC}"; return 1; }
    cost=$(jq -r '.usage.cost // "?"' "$resp_file"); rm -f "$resp_file"
  fi
  magick "$raw_file" -resize "${resize}^" -gravity center -extent "$resize" "$resized"
  cwebp -q 85 "$resized" -o "$output_path" 2>/dev/null
  echo -e "\r  ${GREEN}✓ $filename.webp${NC} (\$${cost}) → $output_dir/"
  rm -f "$resized"
}

process_category() {
  local json_file="$PROMPTS_DIR/$1.json"
  [[ -f "$json_file" ]] || { echo -e "${RED}缺 $json_file${NC}"; exit 1; }
  local count; count=$(jq length "$json_file")
  echo -e "\n${BOLD}📦 $1${NC}($count 张,model: $MODEL)\n"
  local success=0 fail=0
  for i in $(seq 0 $((count-1))); do
    if generate_one "$(jq -r ".[$i].id" "$json_file")" "$(jq -r ".[$i].prompt" "$json_file")" \
      "$(jq -r ".[$i].aspect_ratio" "$json_file")" "$(jq -r ".[$i].resize" "$json_file")" \
      "$(jq -r ".[$i].output_dir" "$json_file")" "$(jq -r ".[$i].filename" "$json_file")"; then ((success++)); else ((fail++)); fi
    [[ $i -lt $((count-1)) ]] && sleep "$DELAY"
  done
  echo -e "\n   完成: ${GREEN}$success 成功${NC} ${RED}$fail 失败${NC}(失败见 $FAILED_LOG)"
}

[[ $# -eq 0 ]] && usage
COMMAND="$1"; shift
CATEGORY=""; ITEM_ID=""; MODEL="$DEFAULT_MODEL"; FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2;;
    --force) FORCE=true; shift;;
    --delay) DELAY="$2"; shift 2;;
    --help|-h) usage;;
    *) if [[ -z "$CATEGORY" ]]; then CATEGORY="$1"; elif [[ -z "$ITEM_ID" ]]; then ITEM_ID="$1"; fi; shift;;
  esac
done

case "$COMMAND" in
  test)
    [[ -z "$CATEGORY" || -z "$ITEM_ID" ]] && { echo "用法: $0 test <category> <id>"; exit 1; }
    check_deps; check_api_key
    local_json="$PROMPTS_DIR/$CATEGORY.json"
    item=$(jq --arg id "$ITEM_ID" '.[] | select(.id == $id)' "$local_json")
    [[ -z "$item" ]] && { echo "id '$ITEM_ID' 不在 $CATEGORY 里:"; jq -r '.[].id' "$local_json" | sed 's/^/  /'; exit 1; }
    echo -e "${BOLD}🧪 单张试生成${NC}(model: $MODEL)\n"
    generate_one "$(echo "$item"|jq -r .id)" "$(echo "$item"|jq -r .prompt)" "$(echo "$item"|jq -r .aspect_ratio)" \
      "$(echo "$item"|jq -r .resize)" "$(echo "$item"|jq -r .output_dir)" "$(echo "$item"|jq -r .filename)";;
  batch)
    [[ -z "$CATEGORY" ]] && { echo "用法: $0 batch <category>"; exit 1; }
    check_deps; check_api_key; process_category "$CATEGORY";;
  list)
    for cat in ${CATEGORY:-$CATEGORIES}; do
      f="$PROMPTS_DIR/$cat.json"; [[ -f "$f" ]] && { echo "${BOLD}$cat${NC}($(jq length "$f") 张):"; jq -r '.[] | "  \(.id) — \(.name)"' "$f"; echo; }
    done;;
  *) echo "未知命令: $COMMAND"; usage;;
esac
