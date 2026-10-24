#!/usr/bin/env bash
# cb_run.sh — 以"监督者模式"调用 CodeBuddy CLI
#
# 用法:
#   cb_run.sh --plan   "任务描述" [cwd] [model] [--session-id 名称]   # 只出方案，不写文件不跑命令
#   cb_run.sh --exec   "任务描述" [cwd] [model] [--session-id 名称]   # 真正执行
#   cb_run.sh --help
#
# 选项:
#   --session-id <名称>  透传 CodeBuddy 的 --session-id，保持会话连续性；
#                        会话名按业务方向取，沿用 references/sessions.md 映射表；
#                        不提供则该参数省略（向后兼容）。
#
# 默认值:
#   cwd   = ~/workspace
#   model = hy3 (免费, 0 积分)
#
# 退出码:
#   0  正常完成
#   2  参数错误
#   3  执行后扫描到黑名单命令（即使命令跑成功了也要报警）

set -uo pipefail

MODE=""
PROMPT=""
CWD="${CB_CWD:-$HOME/workspace}"
MODEL="${CB_MODEL:-hy3}"
SESSION_ID=""

usage() {
  sed -n '2,17p' "$0"
  exit 2
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)  MODE="plan";  shift ;;
    --exec)  MODE="exec";  shift ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [[ $# -gt 0 ]]; do POSITIONAL+=("$1"); shift; done; break ;;
    -*) echo "未知参数: $1" >&2; usage ;;
    *)  POSITIONAL+=("$1"); shift ;;
  esac
done

[[ -z "$MODE" ]] && { echo "必须指定 --plan 或 --exec" >&2; usage; }
PROMPT="${POSITIONAL[0]:-}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && CWD="${POSITIONAL[1]}"
[[ ${#POSITIONAL[@]} -ge 3 ]] && MODEL="${POSITIONAL[2]}"
[[ -z "$PROMPT" ]] && { echo "缺少任务描述" >&2; usage; }

# 说明：命令行 --disallowedTools 黑名单已移除，回归 SKILL.md「权限与黑名单」的三层防护
# （Doubao 自身 Bash 检查 + 文档流程审核 + CLI 权限询问）。下方后置日志扫描只报警不拦截。

# 根据模式调整 prompt 和权限
# 注意：-p 是非交互模式，exec 必须用 --dangerously-skip-permissions，
# 否则写文件/执行命令会被静默拦截（--permission-mode bypassPermissions 不能替代它）。
if [[ "$MODE" == "plan" ]]; then
  PERM_ARGS=(--permission-mode dontAsk)
  INSTRUCTION="$(cat <<'EOF'
你现在只输出方案，不写任何文件、不执行任何 shell 命令。
方案必须包含四项（对齐 SKILL.md「阶段2：商讨方案」的方案四要素）：
1. 目标：这次要达成什么（一句话 + 验收边界）
2. 步骤：有序的执行步骤（每步改哪些文件 / 跑哪些命令，颗粒度对齐任务分级口径）
3. 验证方式：怎么证明做完了（命令 / 预期输出 / 自测）
4. 风险点：不可逆动作、副作用、需要用户拍板或走双闸门的隐患（逐条列出）
不要写任何 .md 草稿文件，全部直接打屏输出。
如果任务本身就需要交付一份 .md 文档作为产物，明确标注"交付物"。
EOF
)"
  FULL_PROMPT="$INSTRUCTION

=== 任务 ===
$PROMPT"
else
  PERM_ARGS=(--dangerously-skip-permissions)
  INSTRUCTION="$(cat <<'EOF'
开始执行任务。约束：
- 不要写任何中间稿/思考过程类的 .md 文件，全部直接打屏输出。
- 如果任务本身的交付物就是 .md 文档（如 README、设计文档），可以写。
- 遇到不确定的需求点，不要硬拍板，打屏输出疑问并停下，等用户澄清。
- 完成后打屏输出：改了哪些文件、跑了哪些命令、验证结果如何。
EOF
)"
  FULL_PROMPT="$INSTRUCTION

=== 任务 ===
$PROMPT"
fi

mkdir -p "$CWD"
cd "$CWD" || { echo "无法进入目录: $CWD" >&2; exit 2; }

echo "[cb_run] mode=$MODE model=$MODEL cwd=$CWD session=${SESSION_ID:-<none>}" >&2

# 记录执行前日志目录状态，执行后只扫描新增日志
LOG_DIR="$HOME/.codebuddy/logs/$(date +%Y-%m-%d)"
mkdir -p "$LOG_DIR"
BEFORE_FILES=$(ls -1 "$LOG_DIR" 2>/dev/null | sort)

# --session-id 透传：提供了才组装，未提供则省略（向后兼容，不在脚本里硬编码任何 session 名）
SESSION_ARGS=()
[[ -n "$SESSION_ID" ]] && SESSION_ARGS=(--session-id "$SESSION_ID")

codebuddy -p \
  --output-format text \
  "${PERM_ARGS[@]}" \
  --autocompact auto \
  "${SESSION_ARGS[@]+"${SESSION_ARGS[@]}"}" \
  --model "$MODEL" \
  "$FULL_PROMPT"
CB_EXIT=$?

# 执行后扫描新增日志，找黑名单关键词
AFTER_FILES=$(ls -1 "$LOG_DIR" 2>/dev/null | sort)
NEW_LOGS=$(comm -13 <(echo "$BEFORE_FILES") <(echo "$AFTER_FILES"))

ALERT=0
if [[ -n "$NEW_LOGS" ]]; then
  echo "" >&2
  echo "[cb_run] === 执行后黑名单扫描 ===" >&2
  for log in $NEW_LOGS; do
    # 在日志里找危险命令关键词
    # 排除启动行（含 argv= / [Dispatch] 的行是命令回显，不是实际执行）
    HITS=$(grep -nE 'rm -rf (\$HOME|~|/ |/workspace)|sudo |mkfs|dd if=|git push (-f|--force)|git reset --hard|DROP (TABLE|DATABASE)|TRUNCATE|:\(\)\{' "$LOG_DIR/$log" 2>/dev/null \
            | grep -v -- 'argv=' \
            | grep -v -- '\[Dispatch\]' \
            | head -20 || true)
    if [[ -n "$HITS" ]]; then
      ALERT=1
      echo "[cb_run] ⚠️  日志 $log 中发现疑似黑名单命令:" >&2
      echo "$HITS" >&2
    fi
  done
  [[ "$ALERT" == "0" ]] && echo "[cb_run] 未发现黑名单命令" >&2
fi

if [[ "$CB_EXIT" -ne 0 ]]; then
  echo "[cb_run] codebuddy 退出码非零: $CB_EXIT" >&2
  exit "$CB_EXIT"
fi

[[ "$ALERT" == "1" ]] && exit 3
exit 0
