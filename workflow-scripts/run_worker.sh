#!/usr/bin/env bash
# run_worker.sh — 派单给便宜劳力(Cursor cursor-agent / Codex CLI)。四种模式(见下 env flag):
#   ① 执行     :worker 改代码(不 commit),报告落 report.md
#   ② 独立验收 :另一个 agent 结合 git diff 挑刺,产出结构化 findings(见 review-preamble.md)
#                双验收时**两个验收员并行跑**(互无依赖:各读同一份已冻工作树、各写各的验收单);
#                一员死(超时/空产出)但另一员产出可解析验收单 → 按存活者派生 + 自曝死者,不整轮报废。
#   回到 planner 的**只有**:STATUS + findings 摘要(含 nit 自曝清单)+ 机器事实 + 验收单 + git stat + token 用量。
#   派发统一走 call_agent.sh(worker=write、验收=read-only);本脚本只做编排。
#   worker/验收 prompt 开头都会附上 agent-discipline.md(常驻六条纪律),不靠各 harness 的 AGENTS 自动加载。
#
# 用法:  scripts/workflow/run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]
#   默认(无 env flag): ①执行 + ②施工审(第4参给第二审 = 双验收并行)。
#   环境变量 SKIP_REVIEW=1   : 跳过②(琐碎/小改分档用);越界校验仍跑。
#   环境变量 REVIEW_ONLY=1   : 跳过①,只对当前工作树跑②。与 SKIP_REVIEW 互斥。
#   环境变量 WO_REVIEW=1     : 跳过①,只跑 WO 审(wo-review-preamble),无 pytest/越界/check_docs 机器事实。
#   环境变量 RUN_WORKER_INTENT_CHECK_ONLY=1 : 仅校验工单意图行后退出(测试桩)。
set -euo pipefail

WO="${1:?用法: run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_timeout.sh
. "$SCRIPT_DIR/lib_timeout.sh"

[ -f "$ROOT/.claude/workflow.env" ] && . "$ROOT/.claude/workflow.env"

MODEL="${2:-${WF_WORKER_MODEL:-cursor/composer-2.5}}"
REVIEW_MODEL="${3:-${WF_REVIEW_MODEL:-cursor/gpt-5.6-luna-max}}"
REVIEW_MODEL_2="${4:-}"

CALL_AGENT="$SCRIPT_DIR/call_agent.sh"
DERIVE_STATUS="$SCRIPT_DIR/derive_status.sh"
[ -x "$CALL_AGENT" ] || { echo "✗ 找不到可执行的 call_agent.sh: $CALL_AGENT" >&2; exit 1; }
[ -x "$DERIVE_STATUS" ] || { echo "✗ 找不到可执行的 derive_status.sh: $DERIVE_STATUS" >&2; exit 1; }

if [ "${REVIEW_ONLY:-0}" = "1" ] && [ "${SKIP_REVIEW:-0}" = "1" ]; then
  echo "✗ REVIEW_ONLY=1 与 SKIP_REVIEW=1 互斥,不能同时设置" >&2
  exit 1
fi
if [ "${WO_REVIEW:-0}" = "1" ] && { [ "${REVIEW_ONLY:-0}" = "1" ] || [ "${SKIP_REVIEW:-0}" = "1" ]; }; then
  echo "✗ WO_REVIEW=1 与 REVIEW_ONLY/SKIP_REVIEW 互斥" >&2
  exit 1
fi

[ -f "$WO" ] || { echo "✗ 工单文件不存在: $WO" >&2; exit 1; }
command -v jq >/dev/null || { echo "✗ 找不到 jq(解析 token 用量需要)" >&2; exit 1; }

_check_wo_intent () {
  local wo_file="$1"
  local intent
  intent="$(grep -m1 '本单服务' "$wo_file" || true)"
  if [ -z "$intent" ]; then
    echo "✗ 闸门:工单 $wo_file 缺「本单服务 → ADR-…」意图对齐行" >&2
    return 1
  fi
  # 只接受可核对存在性的 durable 决策锚:产品单指 ADR-NNNN(check_docs 能验断链);
  # kit 自身工作指 workflow.md(kit 的 durable 设计权威,恒在)。slug-ADR 曾被接受但 check_docs
  # 无从核实 → 闸门退化成格式检查,故不再接受。
  if ! printf '%s' "$intent" | grep -qE 'ADR-[0-9]{4}|workflow\.md'; then
    echo "✗ 闸门:工单 $wo_file 的「本单服务」意图行未指向 ADR-NNNN 或 workflow.md" >&2
    return 1
  fi
  return 0
}

_check_wo_intent "$WO" || exit 1
if [ "${RUN_WORKER_INTENT_CHECK_ONLY:-0}" = "1" ]; then
  echo "✓ 意图行校验通过: $WO"
  exit 0
fi

WORKER_PREAMBLE="$ROOT/.claude/skills/planner/worker-preamble.md"
REVIEW_PREAMBLE="$ROOT/.claude/skills/planner/review-preamble.md"
WO_REVIEW_PREAMBLE="$ROOT/.claude/skills/planner/wo-review-preamble.md"
if [ "${WO_REVIEW:-0}" = "1" ]; then
  [ -f "$WO_REVIEW_PREAMBLE" ] || { echo "✗ 缺 wo-review-preamble.md" >&2; exit 1; }
else
  [ -f "$WORKER_PREAMBLE" ] && [ -f "$REVIEW_PREAMBLE" ] || { echo "✗ 缺 preamble 文件" >&2; exit 1; }
fi

mkdir -p scratchpad/runs
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${STAMP}-$$"
RUN_DIR="scratchpad/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
LOG="${RUN_DIR}/run.log"
REPORT_FILE="${RUN_DIR}/report.md"

TIMEOUT_WORKER="${WF_TIMEOUT_WORKER:-1800}"
TIMEOUT_REVIEW="${WF_TIMEOUT_REVIEW:-1200}"
TIMEOUT_TEST="${WF_TIMEOUT_TEST:-600}"

# 展开 preamble:开头附常驻六条纪律(不靠各 harness 的 AGENTS 自动加载,直接注进 prompt),再接 preamble 正文。
_expand_preamble () {
  : > "$2"
  if [ -f "$ROOT/agent-discipline.md" ]; then
    cat "$ROOT/agent-discipline.md" >> "$2"
    printf '\n\n' >> "$2"
  fi
  sed -e "s|__TEST_CMD__|${WF_TEST_CMD:-uv run pytest}|g" -e "s|__PY__|${WF_PY:-uv run python}|g" "$1" >> "$2"
}
EXEC_PREAMBLE="${RUN_DIR}/exec-preamble.md"
REVIEW_PREAMBLE_X="${RUN_DIR}/review-preamble.md"
WO_REVIEW_PREAMBLE_X="${RUN_DIR}/wo-review-preamble.md"
if [ "${WO_REVIEW:-0}" != "1" ]; then
  _expand_preamble "$WORKER_PREAMBLE" "$EXEC_PREAMBLE"
  _expand_preamble "$REVIEW_PREAMBLE" "$REVIEW_PREAMBLE_X"
else
  _expand_preamble "$WO_REVIEW_PREAMBLE" "$WO_REVIEW_PREAMBLE_X"
fi

# revision = 验收对象树的不可变快照 hash(含 untracked)。**必须在 worker 改完后算**——否则
# hash 的是派单前的树(不含 worker 改动),审计/复审绑的 revision 名不副实。WO 审无代码,hash 工单内容。
_compute_revision () {
  if [ "${WO_REVIEW:-0}" = "1" ]; then
    sha256sum "$WO" | awk '{print substr($1,1,12)}'
  else
  {
    git rev-parse HEAD
    git diff HEAD
    git ls-files --others --exclude-standard | while IFS= read -r f; do
      printf '%s\0' "$f"
      cat "$f"
    done
  } | sha256sum | awk '{print substr($1,1,12)}'
  fi
}

RO_LABEL=""
[ "${REVIEW_ONLY:-0}" = "1" ] && RO_LABEL="  (REVIEW_ONLY=1,跳过执行)"
[ "${WO_REVIEW:-0}" = "1" ] && RO_LABEL="  (WO_REVIEW=1,工单审)"
{
  echo "▶ 派单     : $WO"
  if [ "${WO_REVIEW:-0}" = "1" ]; then
    echo "▶ 模式     : WO 审(只读)"
  else
    echo "▶ 执行模型 : $MODEL${RO_LABEL}"
  fi
  if [ "${SKIP_REVIEW:-0}" = "1" ]; then
    echo "▶ 审查     : (跳过)"
  elif [ "${WO_REVIEW:-0}" = "1" ]; then
    echo "▶ 审查模型 : $REVIEW_MODEL${REVIEW_MODEL_2:+  +双验收(并行) $REVIEW_MODEL_2}"
  else
    echo "▶ 审查模型 : $REVIEW_MODEL${REVIEW_MODEL_2:+  +双验收(并行) $REVIEW_MODEL_2}"
  fi
  echo "▶ 派单前   : HEAD $(git rev-parse --short HEAD) ($(git branch --show-current))"
  echo "▶ run 目录 : $RUN_DIR"
  echo "────────────────────────────────────────────────────────"
} | tee "$LOG"

set +e
CLI_FAILED=0
RC=0

# ① 执行(write 模式)
if [ "${WO_REVIEW:-0}" = "1" ] || [ "${REVIEW_ONLY:-0}" = "1" ]; then
  RC=0
  echo "── [执行] 跳过执行阶段 ──" | tee -a "$LOG"
else
  echo "── [执行] $MODEL(write)──" | tee -a "$LOG"
  exec_tok="$("$CALL_AGENT" --mode write --out "$REPORT_FILE" --stream-log "$LOG" --timeout "$TIMEOUT_WORKER" \
    "$MODEL" "$EXEC_PREAMBLE" "$WO" 2>>"$LOG")"
  RC=$?
  echo "  [执行] ${exec_tok:-token 见 log}" | tee -a "$LOG"
  [ "$RC" -ne 0 ] && CLI_FAILED=1
fi

# 越界校验(worker 执行后,SKIP_REVIEW 也跑)
OVERREACH=0
if [ "${WO_REVIEW:-0}" != "1" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"
    case "$path" in
      decisions/*|AGENTS.md|architecture.md) OVERREACH=1 ;;
    esac
  done < <(git status --porcelain)
fi

# revision 在 worker 改完后算(见 _compute_revision 注释):hash 的是验收员实际看的那棵树。
REVISION="$(_compute_revision)"

# pytest + check_docs(施工审路径)
PYTEST_RC=0
PYTEST_OUT=""
CHECK_DOCS_RC=0
CHECK_DOCS_OUT=""
if [ "${WO_REVIEW:-0}" != "1" ] && [ "${SKIP_REVIEW:-0}" != "1" ]; then
  echo "── [pytest] ${WF_TEST_CMD:-uv run pytest}──" | tee -a "$LOG"
  PYTEST_OUT="$(run_with_timeout "$TIMEOUT_TEST" bash -c "${WF_TEST_CMD:-uv run pytest}" 2>&1)"
  PYTEST_RC=$?
  printf '%s\n' "$PYTEST_OUT" | tee -a "$LOG" >/dev/null

  CHECK_DOCS_OUT="$(${WF_PY:-uv run python} "$SCRIPT_DIR/check_docs.py" --changed 2>&1)"
  CHECK_DOCS_RC=$?
fi

# ② 独立验收
REVIEW_MODELS=()
REVIEW_FILES=()
if [ "${SKIP_REVIEW:-0}" != "1" ]; then
  REVIEW_MODELS+=("$REVIEW_MODEL"); REVIEW_FILES+=("${RUN_DIR}/review.md")
  if [ -n "$REVIEW_MODEL_2" ]; then
    REVIEW_MODELS+=("$REVIEW_MODEL_2"); REVIEW_FILES+=("${RUN_DIR}/review2.md")
  fi
fi

REVIEW_PIDS=()
for i in "${!REVIEW_MODELS[@]}"; do
  rm="${REVIEW_MODELS[$i]}"; rfile="${REVIEW_FILES[$i]}"
  preamble="$REVIEW_PREAMBLE_X"
  [ "${WO_REVIEW:-0}" = "1" ] && preamble="$WO_REVIEW_PREAMBLE_X"
  echo "── [验收$((i+1))] ${rm}(read-only)──" | tee -a "$LOG"
  "$CALL_AGENT" --mode read-only --out "$rfile" --stream-log "$LOG" --timeout "$TIMEOUT_REVIEW" \
    "$rm" "$preamble" "$WO" >"${rfile}.tok" 2>>"$LOG" &
  REVIEW_PIDS+=($!)
done

REVIEW_RC_ECHO=""
REVIEW_FAIL_COUNT=0
for i in "${!REVIEW_MODELS[@]}"; do
  rm="${REVIEW_MODELS[$i]}"; rfile="${REVIEW_FILES[$i]}"
  wait "${REVIEW_PIDS[$i]}"; rrc=$?
  rtok="$(cat "${rfile}.tok" 2>/dev/null)"
  REVIEW_RC_ECHO+="验收$((i+1))($rm) 退出码: $rrc  ${rtok}"$'\n'
  if [ "$rrc" -ne 0 ] || [ ! -f "$rfile" ]; then
    REVIEW_FAIL_COUNT=$((REVIEW_FAIL_COUNT + 1))
    [ -f "$rfile" ] || REVIEW_RC_ECHO+="验收$((i+1))($rm) 未产出 $rfile"$'\n'
  fi
done
# 只有**全部**验收员都失败(单验收即该员)才整轮 infra_failed;部分失败(双验收里死一个)不报废——
# 全部 REVIEW_FILES 都交给 derive,它把空/缺的判为 dead、按存活者派生并自曝(§0.2 安全降级 + 自曝)。
if [ "${#REVIEW_MODELS[@]}" -gt 0 ] && [ "$REVIEW_FAIL_COUNT" -eq "${#REVIEW_MODELS[@]}" ]; then
  CLI_FAILED=1
fi

# 派生 STATUS
DERIVE_ARGS=(--skip-review "${SKIP_REVIEW:-0}" --pytest-rc "$PYTEST_RC" --overreach "$OVERREACH" --check-docs-rc "$CHECK_DOCS_RC" --cli-failed "$CLI_FAILED")
for rf in "${REVIEW_FILES[@]}"; do
  DERIVE_ARGS+=(--review "$rf")
done
DERIVE_OUT="$("$DERIVE_STATUS" "${DERIVE_ARGS[@]}" 2>&1)"
DERIVE_RC=$?
STATUS_LINE="$(printf '%s\n' "$DERIVE_OUT" | grep '^STATUS:' | head -1)"

set -e

{
  echo ""
  echo "═══════ 回给 planner(只看这段;不回 diff/trace) ═══════"
  echo "revision: $REVISION"
  printf '%s\n' "$STATUS_LINE"
  printf '%s\n' "$DERIVE_OUT"
  echo "执行退出码: $RC"
  printf '%s' "$REVIEW_RC_ECHO"
  echo "──── git status --porcelain(含 untracked) ────"
  git status --porcelain
  echo "──── git diff --stat ────"
  git diff --stat
  echo ""
  for i in "${!REVIEW_FILES[@]}"; do
    rfile="${REVIEW_FILES[$i]}"
    [ -f "$rfile" ] || continue
    echo "──── 独立验收单 $((i+1))/${#REVIEW_FILES[@]}(${REVIEW_MODELS[$i]} · $rfile)────"
    cat "$rfile"
    echo ""
  done
  if [ "${WO_REVIEW:-0}" != "1" ] && [ "${SKIP_REVIEW:-0}" != "1" ]; then
    echo "── pytest ──"
    printf '%s\n' "${PYTEST_OUT:-（无输出）}"
    echo "── 文档结构守护(check_docs --changed)──"
    printf '%s\n' "${CHECK_DOCS_OUT:-（无输出）}"
  fi
  echo ""
  echo "✔ trace/token 全量日志: $LOG"
} | tee -a "$LOG"

# best-effort 敏感串打码
sed -i \
  -e 's/sk-[a-zA-Z0-9_-]\{20,\}/[REDACTED]/g' \
  -e 's/ghp_[a-zA-Z0-9]\{20,\}/[REDACTED]/g' \
  "$LOG" 2>/dev/null || true

if printf '%s' "$STATUS_LINE" | grep -q 'infra_failed'; then
  exit 2
fi
# .done = 「产物已定、可被 /cleaning 按龄 GC」的标记,**不是放行判定**——放行状态看 STATUS(complete/blocked/skipped)。
# blocked 也落 .done(产物已定):它按龄回收,durable 审计痕迹在 dispositions.md + git,不在 ephemeral run 目录。
touch "$RUN_DIR/.done"
exit 0
