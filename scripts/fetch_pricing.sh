#!/usr/bin/env bash
# fetch_pricing.sh — 抓取 CodeBuddy 官方定价页，提示当前价格
#
# 用法:
#   fetch_pricing.sh
#
# 说明:
#   copilot.tencent.com/pricing 是前端动态渲染的 SPA，价格数字由 JS 在运行时拉取，
#   curl/wget 抓到的 HTML 里通常没有具体价格。本脚本尝试抓取并抽取价格关键词，
#   抓不到就提示用户手动打开网页查看，绝不缓存或写死任何价格数字。
#
# 退出码:
#   0  正常（无论是否抓到数字，只要成功给出了指引）
#   1  本机没有可用的抓取工具（curl / wget / gh 都没有）

set -uo pipefail

URL="https://copilot.tencent.com/pricing"
DOC_URL="https://www.codebuddy.ai/docs/zh/ide/Account/credits"
UA="Mozilla/5.0 (compatible; fetch_pricing.sh)"

tmp="$(mktemp -t cb_pricing.XXXXXX)" || { echo "无法创建临时文件" >&2; exit 1; }
trap 'rm -f "$tmp"' EXIT

# 依次尝试 curl / wget / gh
fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -sS -m 25 -L -A "$UA" "$URL" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 25 -U "$UA" -O "$tmp" "$URL"
  elif command -v gh >/dev/null 2>&1; then
    gh api "$URL" >"$tmp" 2>/dev/null
  else
    return 127
  fi
}

manual_hint() {
  cat <<EOF

────────────────────────────────────────────
没能自动拿到价格数字。请手动打开官方页面查看：
  1) 官方定价页   : $URL
  2) 官方积分说明 : $DOC_URL
  3) CLI 查余额   : 登录 codebuddy.ai → 头像 → 个人主页 → 用量
────────────────────────────────────────────
EOF
}

echo "[fetch_pricing] 正在抓取 $URL ..." >&2

fetch
rc=$?
if [[ "$rc" -eq 127 ]]; then
  echo "[fetch_pricing] 本机没有 curl / wget / gh，无法自动抓取。" >&2
  manual_hint
  exit 1
elif [[ "$rc" -ne 0 ]]; then
  echo "[fetch_pricing] 抓取失败（网络错误或站点不可达）。" >&2
  manual_hint
  exit 0
fi

# 从抓到的 HTML 里抽取真正的价格数字（¥/￥/元 等），档位名词不算价格
hits="$(grep -oiE '(¥|￥) ?[0-9]+(\.[0-9]+)?|[0-9]+ ?元' "$tmp" 2>/dev/null \
        | sort | uniq -c | sort -rn | head -40)"

if [[ -n "$hits" ]]; then
  echo
  echo "从页面中抽取到的价格数字："
  echo "$hits"
  echo
  echo "以上为页面文本片段，最终价格以官方定价页为准：$URL"
else
  echo "[fetch_pricing] 页面为动态渲染，HTML 中未包含价格数字。" >&2
  manual_hint
fi

exit 0
