#!/usr/bin/env bash
# test_call_agent_stream.sh — 流式 tee、stdout 隔离、超时杀树。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CALL_AGENT="$SCRIPT_DIR/call_agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/cursor-agent" <<'STUB'
#!/usr/bin/env bash
# 桩 cursor-agent: stream-json + 可选 sleep 子进程
if [ "${1:-}" = "__timeout_test__" ]; then
  sleep 100 &
  wait
  exit 0
fi
SENTINEL="STREAM_SENTINEL_XYZ_12345"
echo '{"type":"text","text":"partial"}'
echo "{\"type\":\"result\",\"result\":\"FINAL_REPORT_${SENTINEL}\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"
sleep 1
STUB
chmod +x "$STUB_DIR/cursor-agent"

PROMPT="$TMP/prompt.md"
printf 'test prompt\n' > "$PROMPT"
OUT="$TMP/out.md"
STREAM_LOG="$TMP/stream.log"

PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$OUT" --stream-log "$STREAM_LOG" \
  cursor/fake-model "$PROMPT" >"$TMP/stdout.txt" 2>"$TMP/stderr.txt" || rc=$?
rc=${rc:-0}

FAIL=0

if grep -q "FINAL_REPORT_STREAM_SENTINEL" "$OUT" 2>/dev/null; then
  echo "✓ --out 落到最终 report"
else
  echo "✗ --out 未含最终 report"
  cat "$OUT" 2>/dev/null || true
  FAIL=1
fi

if grep -q 'STREAM_SENTINEL_XYZ_12345' "$TMP/stdout.txt"; then
  echo "✗ stdout 含流内容(违 D7)"
  cat "$TMP/stdout.txt"
  FAIL=1
elif grep -q 'token 用量' "$TMP/stdout.txt"; then
  echo "✓ stdout 仅 token 行"
else
  echo "✗ stdout 缺 token 行"
  cat "$TMP/stdout.txt"
  FAIL=1
fi

if grep -q 'STREAM_SENTINEL_XYZ_12345' "$STREAM_LOG"; then
  echo "✓ stream-log 含原始流"
else
  echo "✗ stream-log 缺原始流"
  cat "$STREAM_LOG" 2>/dev/null || true
  FAIL=1
fi

# 超时杀子进程
cat > "$STUB_DIR/cursor-agent" <<'STUB2'
#!/usr/bin/env bash
sleep 100 &
child=$!
wait $child
STUB2
chmod +x "$STUB_DIR/cursor-agent"

PATH="$STUB_DIR:$PATH" "$CALL_AGENT" --mode read-only --out "$TMP/out2.md" --timeout 2 \
  cursor/fake "$PROMPT" >/dev/null 2>&1 || timeout_rc=$?
timeout_rc=${timeout_rc:-0}

sleep 1
if pgrep -f "sleep 100" >/dev/null 2>&1; then
  echo "✗ 超时后 sleep 100 子进程仍存活"
  pgrep -af "sleep 100" || true
  FAIL=1
  pkill -f "sleep 100" 2>/dev/null || true
else
  echo "✓ 超时后子进程已杀"
fi

if [ "${timeout_rc:-0}" -ne 0 ]; then
  echo "✓ 超时 call_agent 非零($timeout_rc)"
else
  echo "✗ 超时应非零,实得 $timeout_rc"
  FAIL=1
fi

[ "$FAIL" -eq 0 ]
