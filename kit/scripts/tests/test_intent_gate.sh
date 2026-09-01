#!/usr/bin/env bash
# test_intent_gate.sh — run_worker 意图行闸门(不启 agent)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIT_RW="$SCRIPT_DIR/run_worker.sh"
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

# ADR-NNNN(产品单)与 workflow.md(kit 自身工作)都是合法 durable 锚 → 通过意图校验桩
good_wo="$TMP/good-wo.md"
cat > "$good_wo" <<'EOF'
# 好工单
- **本单服务 → ADR-0007 的意图**: 测试
EOF
if RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$good_wo" >/dev/null 2>&1; then
  echo "✓ ADR-NNNN 意图行通过"
else
  echo "✗ ADR-NNNN 意图行应通过"
  FAIL=$((FAIL + 1))
fi

kit_wo="$TMP/kit-wo.md"
cat > "$kit_wo" <<'EOF'
# kit 工单
- **本单服务 → workflow.md §2.5 的意图**: 测试
EOF
if RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$kit_wo" >/dev/null 2>&1; then
  echo "✓ workflow.md 意图行通过(kit 自身工作)"
else
  echo "✗ workflow.md 意图行应通过"
  FAIL=$((FAIL + 1))
fi

# slug-ADR(无法核实存在性)→ 应拒派
slug_wo="$TMP/slug-wo.md"
cat > "$slug_wo" <<'EOF'
# slug 工单
- **本单服务 → ADR-some-slug 的意图**: 测试
EOF
if RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$slug_wo" >/dev/null 2>&1; then
  echo "✗ slug-ADR 意图行应拒派(check_docs 无从核实)"
  FAIL=$((FAIL + 1))
else
  echo "✓ slug-ADR 意图行拒派"
fi

# settings.json 不含废弃 hook 条目
if grep -rE 'check_wo_intent|doc_guard' "$KIT_ROOT/settings.json" >/dev/null 2>&1; then
  echo "✗ settings.json 仍引用废弃 hook 条目"
  FAIL=$((FAIL + 1))
else
  echo "✓ settings.json 无 check_wo_intent/doc_guard"
fi

[ "$FAIL" -eq 0 ]
