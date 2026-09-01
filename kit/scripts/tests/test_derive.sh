#!/usr/bin/env bash
# test_derive.sh — derive_status.sh 纯 bash 单测(不启 agent)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVE="$SCRIPT_DIR/derive_status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
PASS=0

_assert () {
  local name="$1" expect_status="$2" expect_rc="$3"
  shift 3
  local out rc
  out="$("$DERIVE" "$@" 2>&1)" || rc=$?
  rc=${rc:-0}
  local got
  got="$(printf '%s\n' "$out" | grep '^STATUS:' | head -1 | awk '{print $2}')"
  if [ "$got" = "$expect_status" ] && [ "$rc" -eq "$expect_rc" ]; then
    echo "✓ $name: STATUS=$got rc=$rc"
    PASS=$((PASS + 1))
  else
    echo "✗ $name: 期望 STATUS=$expect_status rc=$expect_rc, 实得 STATUS=$got rc=$rc"
    echo "--- 输出 ---"
    printf '%s\n' "$out"
    FAIL=$((FAIL + 1))
  fi
}

_none () { printf '%s\n' '<<<FINDINGS-NONE>>>' > "$1"; }

_empty () { printf '   \n\n' > "$1"; }   # 空/纯空白 = 验收员死(超时落空文件)

_nit () {
  cat > "$1" <<'EOF'
<<<FINDING
severity: nit
where: test:9
claim: 措辞可改
FINDING>>>
EOF
}

_blocking () {
  cat > "$1" <<'EOF'
<<<FINDING
severity: blocking
where: test:1
claim: 有问题
failure_scenario: 会坏
FINDING>>>
EOF
}

_missing_sev () {
  cat > "$1" <<'EOF'
<<<FINDING
where: test:2
claim: 缺 severity
FINDING>>>
EOF
}

_unclosed () {  # 开了 <<<FINDING 但被截断,无 FINDING>>>
  cat > "$1" <<'EOF'
<<<FINDING
severity: blocking
where: test:3
claim: 报告被截断没有闭合标记
EOF
}

# 1
f1="$TMP/r1.md"; _none "$f1"
_assert "1 NONE+clean→review_complete" review_complete 0 \
  --review "$f1" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 2
f2="$TMP/r2.md"; _blocking "$f2"
_assert "2 blocking→review_blocked" review_blocked 0 \
  --review "$f2" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 3
f3="$TMP/r3.md"; _none "$f3"
_assert "3 pytest fail→review_blocked" review_blocked 0 \
  --review "$f3" --skip-review 0 --pytest-rc 1 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 4
f4="$TMP/r4.md"; _none "$f4"
_assert "4 overreach→review_blocked" review_blocked 0 \
  --review "$f4" --skip-review 0 --pytest-rc 0 --overreach 1 --check-docs-rc 0 --cli-failed 0

# 5
f5="$TMP/r5.md"; _none "$f5"
_assert "5 check_docs fail→review_blocked" review_blocked 0 \
  --review "$f5" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 1 --cli-failed 0

# 6
f6="$TMP/r6.md"; printf '空报告无标记\n' > "$f6"
_assert "6 不可解析→infra_failed" infra_failed 2 \
  --review "$f6" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 7
_assert "7 SKIP_REVIEW+clean→review_skipped" review_skipped 0 \
  --skip-review 1 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 8
_assert "8 SKIP_REVIEW+overreach→review_blocked" review_blocked 0 \
  --skip-review 1 --pytest-rc 0 --overreach 1 --check-docs-rc 0 --cli-failed 0

# 9
f9a="$TMP/r9a.md"; f9b="$TMP/r9b.md"; _none "$f9a"; _blocking "$f9b"
_assert "9 双验并集 blocking→review_blocked" review_blocked 0 \
  --review "$f9a" --review "$f9b" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 10
f10="$TMP/r10.md"; _missing_sev "$f10"
out10="$("$DERIVE" --review "$f10" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0 2>&1)" || rc10=$?
rc10=${rc10:-0}
got10="$(printf '%s\n' "$out10" | grep '^STATUS:' | head -1 | awk '{print $2}')"
if [ "$got10" = "review_blocked" ] && [ "$rc10" -eq 0 ] && printf '%s\n' "$out10" | grep -q '缺 severity'; then
  echo "✓ 10 缺 severity 降级 blocking+自曝: STATUS=$got10 rc=$rc10"
  PASS=$((PASS + 1))
else
  echo "✗ 10 缺 severity: 期望 review_blocked rc=0 含自曝, 实得 STATUS=$got10 rc=$rc10"
  printf '%s\n' "$out10"
  FAIL=$((FAIL + 1))
fi

# 11 — 未闭合块(截断报告)→ infra_failed(§0.2)
f11="$TMP/r11.md"; _unclosed "$f11"
_assert "11 未闭合块→infra_failed" infra_failed 2 \
  --review "$f11" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 12 — 双验收一死(空)一活(blocking):任一验收员无有效产出 → 整轮 infra_failed(自曝),不按存活者派生
f12a="$TMP/r12a.md"; f12b="$TMP/r12b.md"; _empty "$f12a"; _blocking "$f12b"
out12="$("$DERIVE" --review "$f12a" --review "$f12b" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0 2>&1)" || rc12=$?
rc12=${rc12:-0}
got12="$(printf '%s\n' "$out12" | grep '^STATUS:' | head -1 | awk '{print $2}')"
if [ "$got12" = "infra_failed" ] && [ "$rc12" -eq 2 ] && printf '%s\n' "$out12" | grep -q '不可解析'; then
  echo "✓ 12 双验收一死→整轮 infra_failed+自曝: STATUS=$got12 rc=$rc12"
  PASS=$((PASS + 1))
else
  echo "✗ 12: 期望 infra_failed rc=2 含自曝, 实得 STATUS=$got12 rc=$rc12"
  printf '%s\n' "$out12"
  FAIL=$((FAIL + 1))
fi

# 13 — 单验收空:无结论 → infra_failed
f13="$TMP/r13.md"; _empty "$f13"
_assert "13 单验收空→infra_failed" infra_failed 2 \
  --review "$f13" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 14 — 纯 nit:review_complete + nit 自曝清单
f14="$TMP/r14.md"; _nit "$f14"
out14="$("$DERIVE" --review "$f14" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0 2>&1)" || rc14=$?
rc14=${rc14:-0}
got14="$(printf '%s\n' "$out14" | grep '^STATUS:' | head -1 | awk '{print $2}')"
if [ "$got14" = "review_complete" ] && [ "$rc14" -eq 0 ] && printf '%s\n' "$out14" | grep -q 'nit 自曝清单'; then
  echo "✓ 14 纯 nit→review_complete+自曝清单: STATUS=$got14 rc=$rc14"
  PASS=$((PASS + 1))
else
  echo "✗ 14: 期望 review_complete rc=0 含 nit 清单, 实得 STATUS=$got14 rc=$rc14"
  printf '%s\n' "$out14"
  FAIL=$((FAIL + 1))
fi

# 15 — glued opener(紧贴文本的 <<<FINDING)→ blocking 计入(回归:此前整块漏计)
f15="$TMP/r15.md"
cat > "$f15" <<'EOF'
先读 diff。以下紧贴文本:检查通过。<<<FINDING
severity: blocking
where: test:15
claim: 紧贴文本的 blocking
FINDING>>>
EOF
out15="$("$DERIVE" --review "$f15" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0 2>&1)" || rc15=$?
rc15=${rc15:-0}
got15="$(printf '%s\n' "$out15" | grep '^STATUS:' | head -1 | awk '{print $2}')"
if [ "$got15" = "review_blocked" ] && [ "$rc15" -eq 0 ] && printf '%s\n' "$out15" | grep -q 'blocking=1'; then
  echo "✓ 15 glued opener→blocking 计入: STATUS=$got15 rc=$rc15"
  PASS=$((PASS + 1))
else
  echo "✗ 15 glued opener: 期望 review_blocked 且 blocking=1, 实得 STATUS=$got15 rc=$rc15"
  printf '%s\n' "$out15"
  FAIL=$((FAIL + 1))
fi

# 16 — glued NONE(紧贴文本的 <<<FINDINGS-NONE>>>)→ review_complete
f16="$TMP/r16.md"
printf '正文结束。<<<FINDINGS-NONE>>>\n' > "$f16"
_assert "16 glued NONE→review_complete" review_complete 0 \
  --review "$f16" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 17 — CRLF 行尾(Windows 产物)→ 仍能解析
f17="$TMP/r17.md"
printf '<<<FINDING\r\nseverity: blocking\r\nwhere: test:17\r\nclaim: CRLF\r\nFINDING>>>\r\n' > "$f17"
_assert "17 CRLF→review_blocked" review_blocked 0 \
  --review "$f17" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

# 18 — marker 行尾空白 → 仍能解析
f18="$TMP/r18.md"
printf '<<<FINDING   \nseverity: blocking\nwhere: test:18\nclaim: 尾随空格\nFINDING>>>  \n' > "$f18"
_assert "18 行尾空白→review_blocked" review_blocked 0 \
  --review "$f18" --skip-review 0 --pytest-rc 0 --overreach 0 --check-docs-rc 0 --cli-failed 0

echo "── 合计: $PASS 通过, $FAIL 失败 ──"
[ "$FAIL" -eq 0 ]
