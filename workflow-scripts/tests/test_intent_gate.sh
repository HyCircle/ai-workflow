#!/usr/bin/env bash
# test_intent_gate.sh — run_worker 意图行闸门(不启 agent)。
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
KIT_RW="$ROOT/workflow-kit/workflow-scripts/run_worker.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0

# 无意图行 → 拒派非零
bad_wo="$TMP/bad-wo.md"
printf '# 坏工单\n无意图行\n' > "$bad_wo"
if "$KIT_RW" "$bad_wo" 2>/dev/null; then
  echo "✗ 无意图行 WO 应非零退出"
  FAIL=$((FAIL + 1))
else
  echo "✓ 无意图行 WO 拒派(非零)"
fi

# ADR-workflow-trust-refactor → 通过意图校验桩
good_wo="$TMP/good-wo.md"
cat > "$good_wo" <<'EOF'
# 好工单
- **本单服务 → ADR-workflow-trust-refactor 的意图**: 测试
EOF
if RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$good_wo" >/dev/null 2>&1; then
  echo "✓ ADR-workflow-trust-refactor 意图行通过"
else
  echo "✗ ADR-workflow-trust-refactor 意图行应通过"
  FAIL=$((FAIL + 1))
fi

# hooks 已摘除
if grep -rE 'check_wo_intent|doc_guard' "$ROOT/workflow-kit/claude/settings.json" >/dev/null 2>&1; then
  echo "✗ settings.json 仍引用已删 hook"
  FAIL=$((FAIL + 1))
else
  echo "✓ settings.json 无 check_wo_intent/doc_guard"
fi

[ "$FAIL" -eq 0 ]
