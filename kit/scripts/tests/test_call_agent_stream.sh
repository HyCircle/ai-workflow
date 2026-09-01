#!/usr/bin/env bash
# test_call_agent_stream.sh — 流式 tee、stdout 隔离、超时杀树 + 报告提取的三种失败形态。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CALL_AGENT="$SCRIPT_DIR/call_agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR"

FAIL=0

_write_stub () { cat > "$STUB_DIR/cursor-agent"; chmod +x "$STUB_DIR/cursor-agent"; }

PROMPT="$TMP/prompt.md"
printf 'test prompt\n' > "$PROMPT"

# ─────────────────────────────────────────────────────────────
# 段1:正常收尾。真实形态 result 带 subtype:success;流里先有 thinking delta(top-level .text)
#      与 assistant(嵌套 .text)——两者都**不得**成为报告,只 success result 的 .result 算数。
# ─────────────────────────────────────────────────────────────
_write_stub <<'STUB'
#!/usr/bin/env bash
SENTINEL="STREAM_SENTINEL_XYZ_12345"
echo '{"type":"thinking","subtype":"delta","text":"THINKING_NOISE_must_not_be_report"}'
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"opening only"}]}}'
echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"FINAL_REPORT_${SENTINEL}\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"
sleep 1
STUB

OUT="$TMP/out.md"; STREAM_LOG="$TMP/stream.log"
rc=0
PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$OUT" --stream-log "$STREAM_LOG" \
  cursor/fake-model "$PROMPT" >"$TMP/stdout.txt" 2>"$TMP/stderr.txt" || rc=$?

if grep -q "FINAL_REPORT_STREAM_SENTINEL" "$OUT" 2>/dev/null; then
  echo "✓ --out 落到最终 report"
else
  echo "✗ --out 未含最终 report"; cat "$OUT" 2>/dev/null || true; FAIL=1
fi

if grep -q 'THINKING_NOISE' "$OUT" 2>/dev/null; then
  echo "✗ thinking 碎片污染了 --out(last-wins 回归)"; cat "$OUT"; FAIL=1
else
  echo "✓ thinking 增量未污染 --out"
fi

if grep -q 'STREAM_SENTINEL_XYZ_12345' "$TMP/stdout.txt"; then
  echo "✗ stdout 含流内容(违 D7)"; cat "$TMP/stdout.txt"; FAIL=1
elif grep -q 'token 用量' "$TMP/stdout.txt"; then
  echo "✓ stdout 仅 token 行"
else
  echo "✗ stdout 缺 token 行"; cat "$TMP/stdout.txt"; FAIL=1
fi

if grep -q 'STREAM_SENTINEL_XYZ_12345' "$STREAM_LOG"; then
  echo "✓ stream-log 含原始流"
else
  echo "✗ stream-log 缺原始流"; cat "$STREAM_LOG" 2>/dev/null || true; FAIL=1
fi

# ─────────────────────────────────────────────────────────────
# 段2:超时杀树。stub 派生 sleep 313 并 wait;到点 timeout 应连整组一起杀,call_agent 非零。
# ─────────────────────────────────────────────────────────────
_write_stub <<'STUB'
#!/usr/bin/env bash
sleep 313 &
wait
STUB

timeout_rc=0
PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$TMP/out2.md" --timeout 2 \
  cursor/fake "$PROMPT" >/dev/null 2>&1 || timeout_rc=$?

sleep 1
if pgrep -f 'sleep 313' >/dev/null 2>&1; then
  echo "✗ 超时后 sleep 313 子进程仍存活"; pgrep -af 'sleep 313' || true; pkill -f 'sleep 313' 2>/dev/null || true; FAIL=1
else
  echo "✓ 超时后子进程已杀"
fi

if [ "$timeout_rc" -ne 0 ]; then
  echo "✓ 超时 call_agent 非零($timeout_rc)"
else
  echo "✗ 超时应非零,实得 $timeout_rc"; FAIL=1
fi

# ─────────────────────────────────────────────────────────────
# 段3:agent 报错(error result)。不得当成有效报告,应非零 + --out 写 AGENT-ERROR。
# ─────────────────────────────────────────────────────────────
_write_stub <<'STUB'
#!/usr/bin/env bash
echo '{"type":"thinking","subtype":"delta","text":"noise"}'
echo '{"type":"result","subtype":"error","is_error":true,"result":"rate limited"}'
STUB

err_rc=0
PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$TMP/out3.md" \
  cursor/fake "$PROMPT" >/dev/null 2>&1 || err_rc=$?

if [ "$err_rc" -ne 0 ] && grep -q 'AGENT-ERROR' "$TMP/out3.md" 2>/dev/null; then
  echo "✓ error result → 非零($err_rc)+ --out 写 AGENT-ERROR"
else
  echo "✗ error result 未 fail-loud(rc=$err_rc)"; cat "$TMP/out3.md" 2>/dev/null || true; FAIL=1
fi

# ─────────────────────────────────────────────────────────────
# 段4:流截断(只有 thinking/assistant,无 result 事件)。应非零 + --out 写 AGENT-STREAM-TRUNCATED,
#      绝不静默丢一个 thinking 碎片。
# ─────────────────────────────────────────────────────────────
_write_stub <<'STUB'
#!/usr/bin/env bash
echo '{"type":"thinking","subtype":"delta","text":"only thinking, never a result event"}'
echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"opening only"}]}}'
STUB

trunc_rc=0
PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$TMP/out4.md" \
  cursor/fake "$PROMPT" >/dev/null 2>&1 || trunc_rc=$?

if [ "$trunc_rc" -ne 0 ] && grep -q 'AGENT-STREAM-TRUNCATED' "$TMP/out4.md" 2>/dev/null; then
  echo "✓ 流截断 → 非零($trunc_rc)+ --out 写 AGENT-STREAM-TRUNCATED"
else
  echo "✗ 流截断未 fail-loud(rc=$trunc_rc)"; cat "$TMP/out4.md" 2>/dev/null || true; FAIL=1
fi

[ "$FAIL" -eq 0 ]
