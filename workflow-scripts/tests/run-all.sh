#!/usr/bin/env bash
# run-all.sh — 本地测试门禁:push 前跑一遍,绿了再 push(不上 CI,solo 项目靠本地纪律)。
# 用法: bash workflow-scripts/tests/run-all.sh   [WF_PY 可覆盖 python,默认 uv run python]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

FAIL=0
run () { echo "── $1 ──"; bash "$HERE/$1"; local rc=$?; [ $rc -eq 0 ] && echo "  ✓ $1" || { echo "  ✗ $1 (rc=$rc)"; FAIL=1; }; echo; }

run test_derive.sh
run test_call_agent_stream.sh
run test_intent_gate.sh
run test_staged.sh
run test_install_smoke.sh

if [ "$FAIL" -eq 0 ]; then echo "全绿 ✓ —— 可 push"; else echo "有失败 ✗ —— 别 push"; fi
exit $FAIL
