#!/usr/bin/env bash
# 运行投影后的真实 run_worker/call_agent/derive/check_docs；仅模型 CLI 用受控进程替代。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
unset SKIP_REVIEW REVIEW_ONLY WO_REVIEW RUN_WORKER_INTENT_CHECK_ONLY
KIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo/.workflow" "$TMP/bin" "$TMP/artifacts"
cp -R "$KIT_ROOT" "$TMP/repo/.workflow/kit"
cd "$TMP/repo"
git init -q
git config user.name test
git config user.email test@example.invalid
printf '/.workflow/\n' >> .git/info/exclude
printf 'VALUE = 0\n' > result.py
cat > verify_result.py <<'PY'
from pathlib import Path
from result import VALUE
Path('.workflow/scratchpad/tests-ran').write_text('executed')
assert VALUE == 1
PY
printf '__pycache__/\n' > .gitignore
git add result.py verify_result.py .gitignore
git commit -qm baseline
cat > .workflow/workflow.env <<'ENV'
WF_WORKER_MODEL=cursor/worker
WF_REVIEW_MODEL=cursor/reviewer
WF_REVIEW_MODEL_STRONG=cursor/reviewer2
WF_TEST_CMD="python3 verify_result.py"
WF_PY=python3
ENV

cat > "$TMP/bin/cursor-agent" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
prompt='' model=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p) prompt="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$prompt" > "$WF_TEST_ARTIFACTS/$model.prompt"
printf '%s\n' "$model" >> "$WF_TEST_ARTIFACTS/calls"
if [ "$model" = worker ]; then
  printf 'VALUE = 1\n' > result.py
  # 执行时原 brief 发生变化，验收仍须消费本轮快照。
  printf '目标：CHANGED_INPUT\n' > "$WF_TEST_SOURCE"
  [ "${WF_TEST_OVERREACH:-0}" = 0 ] || printf '# unauthorized\n' > AGENTS.md
  report=$'结果：已写 result.py。\n偏离：采用简化实现。\n矛盾：候选方案尚需样本验证。\n示例串 sk-abcdefghijklmnopqrstuvwx'
else
  report='<<<FINDINGS-NONE>>>'
fi
jq -nc --arg result "$report" '{type:"result",subtype:"success",is_error:false,result:$result}'
STUB
chmod +x "$TMP/bin/cursor-agent"
export PATH="$TMP/bin:$PATH"
export WF_TEST_ARTIFACTS="$TMP/artifacts"
export WF_TEST_SOURCE="$TMP/source brief.md"
RW="$PWD/.workflow/kit/scripts/run_worker.sh"

require () { if ! "$@"; then echo "✗ $*"; exit 1; fi; }
prepare () {
  printf '目标：ORIGINAL_INPUT\n交付与证据：检查 result.py 的实际行为\n' > "$WF_TEST_SOURCE"
  cp "$WF_TEST_SOURCE" "$TMP/expected.md"
  : > "$WF_TEST_ARTIFACTS/calls"
  rm -f .workflow/scratchpad/tests-ran
}
run_case () {
  local label="$1"
  shift
  if ! "$@" "$RW" "$WF_TEST_SOURCE" > "$TMP/$label.output" 2>&1; then
    cat "$TMP/$label.output"
    return 1
  fi
  RUN_DIR="$(sed -n 's/^▶ run 目录 : //p' "$TMP/$label.output")"
  require test -d "$RUN_DIR"
  require cmp "$TMP/expected.md" "$RUN_DIR/brief.md"
}

prepare
run_case normal env
require grep -q '^STATUS: review_complete$' "$TMP/normal.output"
require test -f .workflow/scratchpad/tests-ran
require test -f "$RUN_DIR/.done"
require grep -q '矛盾：候选方案尚需样本验证' "$TMP/normal.output"
require grep -q '偏离：采用简化实现' "$TMP/normal.output"
require grep -q '\[REDACTED\]' "$TMP/normal.output"
require test "$(cat "$WF_TEST_ARTIFACTS/calls")" = $'worker\nreviewer'
for model in worker reviewer; do
  require grep -q 'ORIGINAL_INPUT' "$WF_TEST_ARTIFACTS/$model.prompt"
  require test "$(grep -c 'CHANGED_INPUT' "$WF_TEST_ARTIFACTS/$model.prompt" || true)" = 0
done
require test "$(grep -c 'sk-abcdefghijklmnopqrstuvwx' "$TMP/normal.output" || true)" = 0
echo '✓ 真实执行/单审入口共用快照，回传偏离矛盾，回显打码，机器检查实际执行'

prepare
dual_run () { "$@" cursor/worker cursor/reviewer cursor/reviewer2; }
run_case dual dual_run
require grep -q '^STATUS: review_complete$' "$TMP/dual.output"
require test -f "$RUN_DIR/review2.md"
require test "$(sort "$WF_TEST_ARTIFACTS/calls")" = $'reviewer\nreviewer2\nworker'
for model in reviewer reviewer2; do
  require grep -q 'ORIGINAL_INPUT' "$WF_TEST_ARTIFACTS/$model.prompt"
  require test "$(grep -c 'CHANGED_INPUT' "$WF_TEST_ARTIFACTS/$model.prompt" || true)" = 0
done
echo '✓ 显式双审均使用执行时的输入快照'

prepare
run_case explore env SKIP_REVIEW=1
require grep -q '^STATUS: review_skipped$' "$TMP/explore.output"
require grep -q '仅越界检查' "$TMP/explore.output"
require grep -q '未执行' "$TMP/explore.output"
require grep -q '矛盾：候选方案尚需样本验证' "$TMP/explore.output"
require test ! -f .workflow/scratchpad/tests-ran
require test "$(cat "$WF_TEST_ARTIFACTS/calls")" = worker
require test ! -f "$RUN_DIR/review.md"
echo '✓ 探索只执行后返回；未执行检查明确可见，不冒充通过'

prepare
run_case review env REVIEW_ONLY=1
require grep -q '^STATUS: review_complete$' "$TMP/review.output"
require test -f .workflow/scratchpad/tests-ran
require test "$(cat "$WF_TEST_ARTIFACTS/calls")" = reviewer
require test ! -f "$RUN_DIR/report.md"
echo '✓ REVIEW_ONLY 接续当前实现，实际运行检查且不重跑 worker'

prepare
run_case plan env WO_REVIEW=1
require grep -q '^STATUS: review_complete$' "$TMP/plan.output"
require grep -q '仅方案审' "$TMP/plan.output"
require grep -q '未执行' "$TMP/plan.output"
require test ! -f .workflow/scratchpad/tests-ran
require test "$(cat "$WF_TEST_ARTIFACTS/calls")" = reviewer
require test ! -f "$RUN_DIR/report.md"
echo '✓ 显式方案审只调用审查员，检查范围与实现验收区分'

prepare
run_case boundary env SKIP_REVIEW=1 WF_TEST_OVERREACH=1
require grep -q '^STATUS: review_blocked$' "$TMP/boundary.output"
require grep -q 'overreach=1' "$TMP/boundary.output"
require test "$(cat "$WF_TEST_ARTIFACTS/calls")" = worker
rm AGENTS.md
echo '✓ 跳过验收仍实际拦出著作文件越界'

prepare
printf 'broken reference ADR-%s\n' 9999 > broken.md
run_case docs env REVIEW_ONLY=1
require grep -q '^STATUS: review_blocked$' "$TMP/docs.output"
require grep -q 'check_docs_rc=1' "$TMP/docs.output"
rm broken.md
echo '✓ 独立审查无 finding 时，真实文档检查失败仍阻断'

prepare
printf 'VALUE = 0\n' > result.py
run_case tests env REVIEW_ONLY=1
require grep -q '^STATUS: review_blocked$' "$TMP/tests.output"
require grep -q 'pytest_rc=1' "$TMP/tests.output"
require grep -q 'pytest: 红(rc=1' "$TMP/tests.output"
require test -f "$RUN_DIR/.done"
echo '✓ 真实行为断言失败时不受无 finding 掩盖'
