#!/usr/bin/env bash
# call_agent.sh — 外呼便宜 agent 的公共入口:流式 tee 进日志,最终报告落 --out;
#   stdout 恒定只有「token 用量」一行(D7)。超时杀整棵进程树。
#
# 用法: call_agent.sh --mode <write|read-only> --out <文件> [--stream-log <file>] [--timeout <秒>]
#       <后端/模型> <prompt文件...>
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
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
text=""; rc=0; usage=""

_redact_stream_log () {
  local log="$1"
  [ -n "$log" ] && [ -f "$log" ] || return 0
  sed -i \
    -e 's/sk-[a-zA-Z0-9_-]\{20,\}/[REDACTED]/g' \
    -e 's/ghp_[a-zA-Z0-9]\{20,\}/[REDACTED]/g' \
    -e 's/gho_[a-zA-Z0-9]\{20,\}/[REDACTED]/g' \
    "$log" 2>/dev/null || true
}

_parse_stream_file () {
  local accum="$1"
  text=""
  usage=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    if printf '%s' "$line" | jq -e '.result // .text // empty' >/dev/null 2>&1; then
      t="$(printf '%s' "$line" | jq -r '.result // .text // empty' 2>/dev/null)"
      [ -n "$t" ] && [ "$t" != "null" ] && text="$t"
    fi
    u="$(printf '%s' "$line" | jq -rc '.usage // empty' 2>/dev/null || true)"
    [ -n "$u" ] && [ "$u" != "null" ] && usage="$u"
  done < "$accum"
  [ -n "$text" ] || text="$(cat "$accum")"
}

_run_cursor () {
  local accum err_file apid pgid wd tailpid
  accum="$(mktemp)"
  err_file="$(mktemp)"

  local -a mode_flags
  if [ "$MODE" = "read-only" ]; then mode_flags=(--mode ask --trust); else mode_flags=(--force --trust); fi

  # 在独立 session 起 agent(setsid → 成组长,便于杀整棵进程树)。流式写 accum 实文件、
  # stderr 落 err_file——redirect 加在外层 setsid 上,参数经 "${@:3}" 原样传入不重排。
  setsid bash -c 'exec cursor-agent -p "$1" --model "$2" "${@:3}" --output-format stream-json' \
    _ "$PROMPT" "$MODEL" "${mode_flags[@]}" >"$accum" 2>"$err_file" &
  apid=$!
  pgid="$(ps -o pgid= -p "$apid" 2>/dev/null | tr -d ' ')"
  [ -n "$pgid" ] || pgid="$apid"

  # 实时把 accum tee 进 stream-log(唯一落点是日志文件;tail --pid 随 agent 结束自退)
  tailpid=""
  if [ -n "$STREAM_LOG" ]; then
    tail -n +1 -f --pid="$apid" "$accum" >> "$STREAM_LOG" 2>/dev/null &
    tailpid=$!
  fi

  # 超时看门狗:到点杀整棵进程组(TERM → 宽限 → KILL)
  wd=""
  if [ "$TIMEOUT_SEC" -gt 0 ] 2>/dev/null; then
    ( sleep "$TIMEOUT_SEC"; kill -TERM "-$pgid" 2>/dev/null; sleep 3; kill -KILL "-$pgid" 2>/dev/null ) &
    wd=$!
  fi

  wait "$apid" 2>/dev/null; rc=$?
  [ -n "$wd" ] && { kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null || true; }
  kill -KILL "-$pgid" 2>/dev/null || true   # 兜底清整组,防 agent 派生的孤儿
  [ -n "$tailpid" ] && { wait "$tailpid" 2>/dev/null || true; }
  [ "$rc" -gt 128 ] && rc=124               # 被信号杀(含超时)归一为 124

  cat "$err_file" >&2
  _parse_stream_file "$accum"
  rm -f "$accum" "$err_file"
}

case "$BACKEND" in
  cursor)
    command -v cursor-agent >/dev/null || { echo "✗ 找不到 cursor-agent" >&2; exit 3; }
    _run_cursor
    ;;
  codex)
    command -v codex >/dev/null || { echo "✗ 找不到 codex" >&2; exit 3; }
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
    # codex 分支为收束后一次性落 stream-log(非实时);cursor 分支实时 tee。
    # 满足 D7 铁律(流只落日志、不上 stdout);实时观测仅 cursor 有,codex 靠收尾落盘事后查。
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
exit "$rc"
