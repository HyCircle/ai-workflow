#!/usr/bin/env bash
# call_agent.sh — 外呼便宜 agent 的公共入口:流式 tee 进日志,最终报告落 --out;
#   stdout 恒定只有「token 用量」一行(D7)。超时连子进程树一起杀。
#
# 用法: call_agent.sh --mode <write|read-only> --out <文件> [--stream-log <file>] [--timeout <秒>]
#       <后端/模型> <prompt文件...>
#
# 退出码:0=正常;124=超时;3=agent 报错(error result);4=流截断(无 success result)。
#   报告提取只认最后一个 {"type":"result","subtype":"success"} 的 .result;拿不到 → fail-loud
#   写显式标记 + 非零退出。thinking/assistant 增量一律不当报告。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib_timeout.sh
. "$SCRIPT_DIR/lib_timeout.sh"

MODE="write"; OUT=""; STREAM_LOG=""; TIMEOUT_SEC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --out)  OUT="${2:-}";  shift 2 ;;
    --stream-log) STREAM_LOG="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:-0}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

SPEC="${1:-}"; shift || true
[ -n "$SPEC" ] || { echo "✗ 用法: call_agent.sh --mode <write|read-only> --out <文件> [--stream-log <file>] [--timeout <秒>] <后端/模型> <prompt文件...>" >&2; exit 2; }
[ -n "$OUT" ]  || { echo "✗ 缺 --out <文件>" >&2; exit 2; }
[ $# -ge 1 ]   || { echo "✗ 缺 prompt 文件" >&2; exit 2; }
[ "$MODE" = "write" ] || [ "$MODE" = "read-only" ] || { echo "✗ --mode 只能是 write|read-only(收到 '$MODE')" >&2; exit 2; }

case "$SPEC" in
  */*) BACKEND="${SPEC%%/*}"; MODEL="${SPEC#*/}" ;;
  *)   BACKEND="cursor";       MODEL="$SPEC" ;;
esac

PROMPT="$(cat "$@")"
# 项目根(worker/验收员的工作目录 -C)按 .workflow 约定定位:从 cwd 上溯找含 .workflow/ 的目录,
# 其身即项目根(monorepo 下 = gitroot)。找不到 → 退回 git-toplevel(kit 自研仓 / 无 .workflow 的旧布局)。
_find_project_root () {
  local d; d="$(pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.workflow" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  git rev-parse --show-toplevel 2>/dev/null
}
ROOT="$(_find_project_root)"
[ -n "$ROOT" ] || { echo "✗ call_agent 须在 git 仓库内(或含 .workflow/ 的项目内)运行" >&2; exit 2; }
text=""; rc=0; usage=""; EXTRACT_RC=0

_redact_stream_log () {
  local log="$1"
  [ -n "$log" ] && [ -f "$log" ] || return 0
  sed -i \
    -e 's/sk-[a-zA-Z0-9_-]\{20,\}/[REDACTED]/g' \
    -e 's/ghp_[a-zA-Z0-9]\{20,\}/[REDACTED]/g' \
    -e 's/gho_[a-zA-Z0-9]\{20,\}/[REDACTED]/g' \
    "$log" 2>/dev/null || true
}

# 从 cursor stream-json(NDJSON)提取最终报告到全局 text、usage。
# 只认最后一个 {"type":"result","subtype":"success"} 的 .result;thinking/assistant 增量一律不当报告。
# 返回:0=成功;3=agent 报错(error result);4=流截断/无 success result(fail-loud,写显式标记)。
_extract_report () {
  local accum="$1"
  text=""; usage=""
  local last_result
  last_result="$(jq -c 'select(.type=="result")' "$accum" 2>/dev/null | tail -1)"
  if [ -z "$last_result" ]; then
    text="$(cat "$accum")
<<<AGENT-STREAM-TRUNCATED: 未收到 result 事件(超时被杀 / 中断 / 后端未收尾);以上为原始流全文>>>"
    return 4
  fi
  usage="$(printf '%s' "$last_result" | jq -rc '.usage // empty' 2>/dev/null || true)"
  local subtype iserr
  subtype="$(printf '%s' "$last_result" | jq -r '.subtype // empty' 2>/dev/null)"
  iserr="$(printf '%s' "$last_result" | jq -r '.is_error // false' 2>/dev/null)"
  if [ "$subtype" = "success" ] && [ "$iserr" != "true" ]; then
    text="$(printf '%s' "$last_result" | jq -r '.result // empty' 2>/dev/null)"
    [ -n "$text" ] && return 0
    text="<<<AGENT-EMPTY-RESULT: result 事件 success 但 .result 为空>>>"
    return 4
  fi
  local errmsg
  errmsg="$(printf '%s' "$last_result" | jq -r '.result // .error // "unknown"' 2>/dev/null)"
  text="<<<AGENT-ERROR: subtype=${subtype:-error}: ${errmsg}>>>"
  return 3
}

_run_cursor () {
  local accum err_file apid tailpid
  accum="$(mktemp)"
  err_file="$(mktemp)"

  local -a mode_flags
  if [ "$MODE" = "read-only" ]; then mode_flags=(--mode ask --trust); else mode_flags=(--force --trust); fi

  # 超时前缀:coreutils timeout 默认杀整个进程树(含 cursor-agent 派生的 node 子进程);
  # TIMEOUT_SEC≤0 时 tmo 为空数组 → 不限时直接跑。stdin 接 /dev/null:审批提示不读终端,不会阻塞。
  local -a tmo=()
  [ "$TIMEOUT_SEC" -gt 0 ] 2>/dev/null && tmo=(timeout -k 5 "$TIMEOUT_SEC")

  "${tmo[@]}" cursor-agent -p "$PROMPT" --model "$MODEL" "${mode_flags[@]}" --output-format stream-json \
    </dev/null >"$accum" 2>"$err_file" &
  apid=$!

  # 实时把 accum tee 进 stream-log(唯一落点是日志文件;tail --pid 随前台命令结束自退)
  tailpid=""
  if [ -n "$STREAM_LOG" ]; then
    tail -n +1 -f --pid="$apid" "$accum" >> "$STREAM_LOG" 2>/dev/null &
    tailpid=$!
  fi

  wait "$apid" 2>/dev/null; rc=$?
  [ -n "$tailpid" ] && { wait "$tailpid" 2>/dev/null || true; }
  { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && rc=124   # 超时归一为 124

  cat "$err_file" >&2
  _extract_report "$accum"; EXTRACT_RC=$?
  rm -f "$accum" "$err_file"
}

case "$BACKEND" in
  cursor)
    command -v cursor-agent >/dev/null || { echo "✗ 找不到 cursor-agent" >&2; exit 3; }
    _run_cursor
    ;;
  codex)
    command -v codex >/dev/null || { echo "✗ 找不到 codex" >&2; exit 3; }
    # codex exec 输出是纯文本(非 NDJSON):整段即报告,无 last-wins 问题;超时靠 run_with_timeout。
    accum="$(mktemp)"
    err_file="$(mktemp)"
    if [ "$TIMEOUT_SEC" -gt 0 ] 2>/dev/null; then
      run_with_timeout "$TIMEOUT_SEC" bash -c 'printf "%s" "$1" | codex exec --dangerously-bypass-approvals-and-sandbox -m "$2" -C "$3" 2>"$4"' \
        _ "$PROMPT" "$MODEL" "$ROOT" "$err_file" >"$accum"
      rc=$?
    else
      printf '%s' "$PROMPT" | codex exec --dangerously-bypass-approvals-and-sandbox -m "$MODEL" -C "$ROOT" 2>"$err_file" >"$accum"
      rc=$?
    fi
    # codex 分支收束后一次性落 stream-log(非实时);满足 D7(流只落日志、不上 stdout)。
    [ -n "$STREAM_LOG" ] && cat "$accum" >> "$STREAM_LOG"
    cat "$err_file" >&2
    text="$(cat "$accum")"
    usage="$(printf '%s\n%s' "$text" "$(cat "$err_file")" | awk '/tokens used/{getline; gsub(/^ +/,""); print; exit}')"
    rm -f "$accum" "$err_file"
    ;;
  *) echo "✗ 未知后端: $BACKEND(只支持 cursor|codex)" >&2; exit 3 ;;
esac

[ -n "$STREAM_LOG" ] && _redact_stream_log "$STREAM_LOG"

mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$text" > "$OUT"
echo "token 用量: ${usage:-未知}"
# 退出码:执行层非零(超时/CLI 失败)优先;否则取解析层(agent 报错/流截断)。
[ "$rc" -eq 0 ] && rc="$EXTRACT_RC"
exit "$rc"
