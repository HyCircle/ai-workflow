#!/usr/bin/env bash
# lib_timeout.sh — setsid 起子进程 + 超时杀整棵进程树(TERM → 宽限 → KILL)。
# 用法: run_with_timeout <秒> <命令...>  ;退出码 = 命令退出码,124 = 超时杀树。
run_with_timeout () {
  local timeout_sec="$1"; shift
  [ "$timeout_sec" -gt 0 ] 2>/dev/null || { "$@"; return $?; }

  local tmp rc pgid watchdog
  tmp="$(mktemp)"
  setsid bash -c '"$@"' _ "$@" >"$tmp" 2>&1 &
  local pid=$!

  sleep 0.1
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  [ -n "$pgid" ] || pgid="$pid"

  (
    sleep "$timeout_sec"
    kill -TERM "-$pgid" 2>/dev/null
    sleep 2
    kill -KILL "-$pgid" 2>/dev/null
  ) &
  watchdog=$!

  wait "$pid" 2>/dev/null; rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null || true
  kill -KILL "-$pgid" 2>/dev/null || true   # 兜底清整组

  cat "$tmp"
  rm -f "$tmp"

  [ "$rc" -gt 128 ] && rc=124   # 被信号杀(含超时)归一为 124
  return "$rc"
}
