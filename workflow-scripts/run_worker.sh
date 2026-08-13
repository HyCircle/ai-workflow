#!/usr/bin/env bash
# run_worker.sh — 派单给便宜劳力(Cursor cursor-agent / Codex CLI)。两阶段:
#   ① 执行     :worker 改代码(不 commit),报告落 report.md
#   ② 独立验收 :另一个 agent 结合 git diff 挑刺,产出简短验收单(结构见 .claude/skills/planner/review-preamble.md)
#                双验收时**两个验收员并行跑**(互无依赖:各读同一份已冻工作树、各写各的验收单)。
#   回到 planner 的**只有**:验收单 + git stat + token 用量。**不回 diff、不回 trace**——
#   这就是省 Opus 的关键:worker 的代码和推理不再灌进 Claude 的 context。
#   派发统一走 call_agent.sh(worker=write、验收=read-only);本脚本只做编排。
#
# 用法:  scripts/workflow/run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]
#   工单文件 : 必填,通常 scratchpad/PL-<id>/WO-current.md
#   模型写法 : 「后端/模型」,后端 = cursor(默认,可省)| codex。
#              例:cursor/composer-2.5 · codex/deepseek-v4-flash · gpt-5.3-codex(省前缀=cursor)
#   执行模型 : 默认 cursor/composer-2.5(用标准档,非 -fast)。硬骨头换 cursor 更强模型 / codex/deepseek-v4-flash。
#   审查模型 : 默认 cursor/gpt-5.6-luna-max(**跨厂异构** worker,真独立第二双眼)。
#   审查模型2: 可选。给了就**双验收**(两单都回 planner 交叉检验,任一 NO-GO 即打回)。高危/复杂用。
#              例:… cursor/composer-2.5 cursor/gpt-5.6-luna-max codex/deepseek-v4-flash
#   环境变量 SKIP_REVIEW=1   : 跳过②(琐碎/小改分档用;见 /planner skill 三档分诊)。
#   环境变量 REVIEW_ONLY=1   : 跳过①,只对当前工作树跑②(轻验收;planner 自改后独立验收)。与 SKIP_REVIEW 互斥。
#
# 上下文分层:无头 worker 自动加载 CLAUDE.md + 全局 karpathy 准则;各阶段前言从 .claude/skills/planner/*-preamble.md 注入。
# 交付物:worker 与验收员的回复各落成一个 md(report.md / review*.md),planner 只读这些 md —— 不回 diff/trace。落盘由 call_agent.sh 统一做,agent 本身只读文件或只改代码。
set -euo pipefail

WO="${1:?用法: run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
# 单一配置源:模型档位 / 命令(见 .claude/workflow.env)。缺文件则退回内置默认。
[ -f "$ROOT/.claude/workflow.env" ] && . "$ROOT/.claude/workflow.env"

MODEL="${2:-${WF_WORKER_MODEL:-cursor/composer-2.5}}"
REVIEW_MODEL="${3:-${WF_REVIEW_MODEL:-cursor/gpt-5.6-luna-max}}"
REVIEW_MODEL_2="${4:-}"   # 双验收=按需 opt-in:planner 显式传第4参(通常 $WF_REVIEW_MODEL_STRONG)才触发;不从 env 自动读,免每单都双验

CALL_AGENT="$ROOT/scripts/workflow/call_agent.sh"
[ -x "$CALL_AGENT" ] || { echo "✗ 找不到可执行的 call_agent.sh: $CALL_AGENT" >&2; exit 1; }

if [ "${REVIEW_ONLY:-0}" = "1" ] && [ "${SKIP_REVIEW:-0}" = "1" ]; then
  echo "✗ REVIEW_ONLY=1 与 SKIP_REVIEW=1 互斥,不能同时设置" >&2
  exit 1
fi

[ -f "$WO" ] || { echo "✗ 工单文件不存在: $WO" >&2; exit 1; }
command -v jq >/dev/null || { echo "✗ 找不到 jq(解析 token 用量需要)" >&2; exit 1; }

WORKER_PREAMBLE="$ROOT/.claude/skills/planner/worker-preamble.md"
REVIEW_PREAMBLE="$ROOT/.claude/skills/planner/review-preamble.md"
[ -f "$WORKER_PREAMBLE" ] && [ -f "$REVIEW_PREAMBLE" ] || { echo "✗ 缺 preamble 文件($WORKER_PREAMBLE / $REVIEW_PREAMBLE)" >&2; exit 1; }

mkdir -p scratchpad/runs
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${STAMP}-$$"
RUN_DIR="scratchpad/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
LOG="${RUN_DIR}/run.log"
REPORT_FILE="${RUN_DIR}/report.md"

# 把命令档从 workflow.env 展开进 preamble(单一配置源:__TEST_CMD__/__PY__ ← WF_TEST_CMD/WF_PY),
# 展开后的副本落 run 目录再交 call_agent —— 让注入 worker/验收员的命令与 planner 读的 env 同源。
EXEC_PREAMBLE="${RUN_DIR}/exec-preamble.md"
REVIEW_PREAMBLE_X="${RUN_DIR}/review-preamble.md"
_expand_preamble () { sed -e "s|__TEST_CMD__|${WF_TEST_CMD:-uv run pytest}|g" -e "s|__PY__|${WF_PY:-uv run python}|g" "$1" > "$2"; }
_expand_preamble "$WORKER_PREAMBLE" "$EXEC_PREAMBLE"
_expand_preamble "$REVIEW_PREAMBLE" "$REVIEW_PREAMBLE_X"

RO_LABEL=""
[ "${REVIEW_ONLY:-0}" = "1" ] && RO_LABEL="  (REVIEW_ONLY=1,跳过执行)"
{
  echo "▶ 派单     : $WO"
  echo "▶ 执行模型 : $MODEL${RO_LABEL}"
  if [ "${SKIP_REVIEW:-0}" = "1" ]; then
    echo "▶ 审查     : (跳过)"
  else
    echo "▶ 审查模型 : $REVIEW_MODEL${REVIEW_MODEL_2:+  +双验收(并行) $REVIEW_MODEL_2}"
  fi
  echo "▶ 派单前   : HEAD $(git rev-parse --short HEAD) ($(git branch --show-current))"
  echo "▶ run 目录 : $RUN_DIR"
  echo "────────────────────────────────────────────────────────"
} | tee "$LOG"

set +e
# ① 执行(write 模式,worker 可改代码;报告打到 stdout → report.md)
if [ "${REVIEW_ONLY:-0}" = "1" ]; then
  RC=0
  echo "── [执行] REVIEW_ONLY=1,跳过执行阶段 ──" | tee -a "$LOG"
else
  echo "── [执行] $MODEL(write)──" | tee -a "$LOG"
  exec_tok="$("$CALL_AGENT" --mode write --out "$REPORT_FILE" "$MODEL" "$EXEC_PREAMBLE" "$WO" 2>>"$LOG")"
  RC=$?
  echo "  [执行] ${exec_tok:-token 见 log}" | tee -a "$LOG"
fi

# ② 独立验收(read-only 模式;1 或 2 个验收员;两个时并行)
REVIEW_MODELS=()
REVIEW_FILES=()
if [ "${SKIP_REVIEW:-0}" != "1" ]; then
  REVIEW_MODELS+=("$REVIEW_MODEL"); REVIEW_FILES+=("${RUN_DIR}/review.md")
  if [ -n "$REVIEW_MODEL_2" ]; then
    REVIEW_MODELS+=("$REVIEW_MODEL_2"); REVIEW_FILES+=("${RUN_DIR}/review2.md")
  fi
fi

# 并行派发:每个验收员后台起 call_agent(约定不改树——见 call_agent 头注;各写各自的 review 文件,输出零冲突),token 落 <file>.tok
REVIEW_PIDS=()
for i in "${!REVIEW_MODELS[@]}"; do
  rm="${REVIEW_MODELS[$i]}"; rfile="${REVIEW_FILES[$i]}"
  echo "── [验收$((i+1))] ${rm}(read-only)──" | tee -a "$LOG"
  "$CALL_AGENT" --mode read-only --out "$rfile" "$rm" "$REVIEW_PREAMBLE_X" "$WO" >"${rfile}.tok" 2>>"$LOG" &
  REVIEW_PIDS+=($!)
done

# 收敛:等每个验收员,读退出码 + 验收单判定
REVIEW_ANY_NOGO=0
REVIEW_ANY_FAIL=""
REVIEW_RC_ECHO=""
REVIEW_NOGO_SUMMARY=""
for i in "${!REVIEW_MODELS[@]}"; do
  rm="${REVIEW_MODELS[$i]}"; rfile="${REVIEW_FILES[$i]}"
  wait "${REVIEW_PIDS[$i]}"; rrc=$?
  rtok="$(cat "${rfile}.tok" 2>/dev/null)"
  REVIEW_RC_ECHO+="验收$((i+1))($rm) 退出码: $rrc  ${rtok}"$'\n'
  if [ "$rrc" -ne 0 ]; then
    REVIEW_ANY_FAIL+="${REVIEW_ANY_FAIL:+;}验收$((i+1))($rm) 退出码 $rrc"
  elif [ ! -f "$rfile" ]; then
    REVIEW_ANY_FAIL+="${REVIEW_ANY_FAIL:+;}验收$((i+1))($rm) 未产出 $rfile"
  elif ! grep -q '^【判定】' "$rfile"; then
    REVIEW_ANY_FAIL+="${REVIEW_ANY_FAIL:+;}验收$((i+1))($rm) 缺【判定】行"
  elif grep -m1 '^【判定】' "$rfile" | grep -q 'NO-GO'; then
    REVIEW_ANY_NOGO=1
    REVIEW_NOGO_SUMMARY+="${REVIEW_NOGO_SUMMARY:+;}验收$((i+1))($rm):$(grep -m1 '^【判定】' "$rfile")"
  fi
done

# 文档结构守护(planner 直接采信,worker 路径也跑一次)
CHECK_DOCS_RC=0
CHECK_DOCS_OUT=""
if [ "${SKIP_REVIEW:-0}" != "1" ]; then
  CHECK_DOCS_OUT="$(${WF_PY:-uv run python} scripts/workflow/check_docs.py --changed 2>&1)"
  CHECK_DOCS_RC=$?
fi
set -e

{
  echo ""
  echo "═══════ 回给 planner(只看这段;不回 diff/trace) ═══════"
  echo "执行退出码: $RC"
  printf '%s' "$REVIEW_RC_ECHO"
  echo "──── git status --porcelain(含 untracked) ────"
  git status --porcelain
  echo "──── git diff --stat ────"
  git diff --stat
  echo ""
  if [ "${SKIP_REVIEW:-0}" = "1" ]; then
    echo "(已跳过②验收;planner 自行 pytest + 抽查)"
  elif [ -n "$REVIEW_ANY_FAIL" ]; then
    echo "✗ 验收未成立: $REVIEW_ANY_FAIL,判 NO-GO,别采信"
  elif [ "$REVIEW_ANY_NOGO" -eq 1 ]; then
    echo "✗ 验收判 NO-GO,打回($REVIEW_NOGO_SUMMARY)"
  fi
  for i in "${!REVIEW_FILES[@]}"; do
    rfile="${REVIEW_FILES[$i]}"
    [ -f "$rfile" ] || continue
    echo "──── 独立验收单 $((i+1))/${#REVIEW_FILES[@]}(${REVIEW_MODELS[$i]} · $rfile)────"
    cat "$rfile"
    echo ""
  done
  if [ "${SKIP_REVIEW:-0}" != "1" ]; then
    echo "── 文档结构守护(check_docs --changed)──"
    printf '%s\n' "${CHECK_DOCS_OUT:-（无输出）}"
    [ "$CHECK_DOCS_RC" -ne 0 ] && echo "⚠ check_docs 退出码 $CHECK_DOCS_RC(文档结构违规,planner 自行判定;不影响脚本退出码)"
  fi
  echo ""
  echo "✔ trace/token 全量日志: $LOG"
  echo "  planner:先读上面的验收单 → 只亲验「需亲验的点」→ 采信则放行 commit(TODO/文档维护交 /cleaning)"
} | tee -a "$LOG"

if [ "$RC" -ne 0 ]; then
  exit "$RC"
elif [ -n "$REVIEW_ANY_FAIL" ]; then
  exit 3
elif [ "$REVIEW_ANY_NOGO" -eq 1 ]; then
  exit 4
fi
touch "$RUN_DIR/.done"
exit 0
