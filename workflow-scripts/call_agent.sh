#!/usr/bin/env bash
# call_agent.sh — 外呼便宜 agent 的公共入口:把一段 prompt 派给外部 agent(cursor-agent / codex),
#   捕获它的**文本输出**落盘到 <out文件>,回显 token 用量。**只做派发 + 落盘**,不做编排。
#
# 这是「Claude 外呼便宜 agent」的唯一通道,三类消费者共用它:
#   ① run_worker.sh 的执行阶段(worker 施工,--mode write)
#   ② run_worker.sh 的验收阶段(独立验收,--mode read-only,可并行多个)
#   ③ bs/planner 的 red-team(冻结前审 options/ADR,--mode read-only)
#   每个外部 agent 的回复都落成一个固定路径的 md,CC 只读那个 md;red-team 批评也就可审阅、可归档。
#
# 用法: call_agent.sh --mode <write|read-only> --out <文件> <后端/模型> <prompt文件...>
#   --mode write     : agent 可改工作树(仅 worker 施工需要)。
#   --mode read-only : agent 只读文件系统、不能改树(验收 / red-team)。
#   --out <文件>     : agent 的文本回复落这里 —— **这就是它的交付物**(报告/验收单/批评正文)。
#   后端/模型        : 「cursor|codex/模型」,省前缀 = cursor。如 codex/deepseek-v4-flash。
#   prompt文件...    : 依次 cat 拼成 prompt(如 preamble + 目标文件)。
# 回显 stdout: 「token 用量: N」一行。返回码 = agent 退出码(找不到 CLI / 参数错 = 2/3)。
set -uo pipefail

MODE="write"; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --out)  OUT="${2:-}";  shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

SPEC="${1:-}"; shift || true
[ -n "$SPEC" ] || { echo "✗ 用法: call_agent.sh --mode <write|read-only> --out <文件> <后端/模型> <prompt文件...>" >&2; exit 2; }
[ -n "$OUT" ]  || { echo "✗ 缺 --out <文件>" >&2; exit 2; }
[ $# -ge 1 ]   || { echo "✗ 缺 prompt 文件" >&2; exit 2; }
[ "$MODE" = "write" ] || [ "$MODE" = "read-only" ] || { echo "✗ --mode 只能是 write|read-only(收到 '$MODE')" >&2; exit 2; }

case "$SPEC" in
  */*) BACKEND="${SPEC%%/*}"; MODEL="${SPEC#*/}" ;;
  *)   BACKEND="cursor";       MODEL="$SPEC" ;;   # 省前缀 = cursor
esac

PROMPT="$(cat "$@")"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
out=""; rc=0; usage=""

case "$BACKEND" in
  cursor)
    command -v cursor-agent >/dev/null || { echo "✗ 找不到 cursor-agent" >&2; exit 3; }
    # read-only = --mode ask(只读规划,不改树);write = --force --trust(免交互放行,可改树)
    if [ "$MODE" = "read-only" ]; then MODE_FLAGS=(--mode ask --trust); else MODE_FLAGS=(--force --trust); fi
    out="$(cursor-agent -p "$PROMPT" --model "$MODEL" "${MODE_FLAGS[@]}" --output-format json 2>/dev/null)"; rc=$?
    # cursor json:文本在 .result,token 在 .usage
    text="$(printf '%s' "$out" | jq -r '.result // .text // .message // empty' 2>/dev/null)"
    [ -n "$text" ] || text="$out"   # 解析不出就落原始输出,别静默丢产物
    usage="$(printf '%s' "$out" | jq -rc '.usage // empty' 2>/dev/null || true)"
    ;;
  codex)
    command -v codex >/dev/null || { echo "✗ 找不到 codex" >&2; exit 3; }
    # read-only = -s read-only;write = --dangerously-bypass-approvals-and-sandbox
    if [ "$MODE" = "read-only" ]; then SANDBOX=(-s read-only); else SANDBOX=(--dangerously-bypass-approvals-and-sandbox); fi
    out="$(printf '%s' "$PROMPT" | codex exec "${SANDBOX[@]}" -m "$MODEL" -C "$ROOT" 2>/dev/null)"; rc=$?
    text="$out"
    # codex plain 输出末尾有「tokens used\n<数字>」,取那个数字
    usage="$(printf '%s' "$out" | awk '/tokens used/{getline; gsub(/^ +/,""); print; exit}')"
    ;;
  *) echo "✗ 未知后端: $BACKEND(只支持 cursor|codex)" >&2; exit 3 ;;
esac

mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$text" > "$OUT"
echo "token 用量: ${usage:-未知}"
exit "$rc"
