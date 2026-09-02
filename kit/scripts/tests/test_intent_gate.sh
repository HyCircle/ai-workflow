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

# ADR-NNNN 是合法 durable 锚 → 通过意图校验桩
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

# 非 ADR-NNNN 锚 → 拒派
_reject_intent () {
  local file_id="$1" label="$2" body="$3"
  local f="$TMP/reject-$file_id.md"
  printf '%s' "$body" > "$f"
  if RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$f" >/dev/null 2>&1; then
    echo "✗ $label 意图行应拒派"
    FAIL=$((FAIL + 1))
  else
    echo "✓ $label 拒派"
  fi
}
_reject_intent design-md docs/design.md $'# kit\n- **本单服务 → docs/design.md §2.5 的意图**: 测试\n'
_reject_intent slug-adr slug-ADR $'# slug\n- **本单服务 → ADR-some-slug 的意图**: 测试\n'

# settings.json 不含废弃 hook 条目
if grep -rE 'check_wo_intent|doc_guard' "$KIT_ROOT/settings.json" >/dev/null 2>&1; then
  echo "✗ settings.json 仍引用废弃 hook 条目"
  FAIL=$((FAIL + 1))
else
  echo "✓ settings.json 无 check_wo_intent/doc_guard"
fi

[ "$FAIL" -eq 0 ]
