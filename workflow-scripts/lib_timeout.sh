#!/usr/bin/env bash
# lib_timeout.sh — 带超时执行:到点连子进程树一起杀,返回命令退出码,124 = 超时。
# 用法: run_with_timeout <秒> <命令...>  ;<秒>≤0 = 不限时直接跑。
#
# 交给 coreutils `timeout`(TERM,-k 宽限后 KILL):默认模式把被管命令放进独立进程组、
# 超时杀整组(实测连孤儿子进程一并清理)。不再手搓 setsid/pgid 看门狗——那套有 pgid
# 读取竞态、且一旦失效上层就永久楔死。
run_with_timeout () {
  local timeout_sec="$1"; shift
  [ "$timeout_sec" -gt 0 ] 2>/dev/null || { "$@"; return $?; }
  timeout -k 5 "$timeout_sec" "$@"
  local rc=$?
  { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && rc=124   # TERM/KILL(超时)归一为 124
  return "$rc"
}
