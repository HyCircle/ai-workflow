#!/usr/bin/env bash
# run_worker.sh — 派单给便宜劳力(Cursor cursor-agent / Codex CLI)。两阶段:
#   ① 执行     :worker 改代码(不 commit)
#   ② 独立验收 :另一个 agent 结合 git diff 挑刺,产出简短验收单(结构见 .claude/skills/planner/review-preamble.md)
#   回到 planner 的**只有**:验收单 + git stat + token 用量。**不回 diff、不回 trace**——
#   这就是省 Opus 的关键:worker 的代码和推理不再灌进 Claude 的 context。
#
# 用法:  scripts/workflow/run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]
#   工单文件 : 必填,通常 scratchpad/WO-current.md
#   模型写法 : 「后端/模型」,后端 = cursor(默认,可省)| codex。
#              例:cursor/composer-2.5 · codex/deepseek-v4-flash · gpt-5.3-codex(省前缀=cursor)
#   执行模型 : 默认 cursor/composer-2.5(**不用 -fast**)。硬骨头换 cursor 更强模型 / codex/deepseek-v4-flash。
#   审查模型 : 默认 codex/deepseek-v4-flash(**跨厂异构** worker,真独立第二双眼;实测 > luna,便宜)。
#   审查模型2: 可选。给了就**双验收**(两单都回 planner 交叉检验,任一 NO-GO 即打回)。高危/复杂用。
#              例:… cursor/composer-2.5 codex/deepseek-v4-flash cursor/gpt-5.6-luna-high
#   环境变量 SKIP_REVIEW=1   : 跳过②(琐碎/小改分档用;见 /planner skill 三档分诊)。
#   环境变量 REVIEW_ONLY=1   : 跳过①,只对当前工作树跑②(轻验收;planner 自改后独立验收)。与 SKIP_REVIEW 互斥。
#
# 后端事实:
#   cursor → cursor-agent -p <prompt> --force --trust --output-format json(--force/--trust 免交互放行)
#   codex  → codex exec --dangerously-bypass-approvals-and-sandbox -m <model> -C <root>(prompt 走 stdin)
#            config 已配 provider=deepseek;两者都是本地开发的全信任模式,别在不受信网络上跑。
# 上下文分层:无头 worker 自动加载 CLAUDE.md + 全局 karpathy 准则;各阶段前言从 .claude/skills/planner/*-preamble.md 注入。
set -euo pipefail

WO="${1:?用法: run_worker.sh <工单文件> [执行模型] [审查模型] [审查模型2]}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
# 单一配置源:模型档位 / 命令(见 .claude/workflow.env)。缺文件则退回内置默认。
[ -f "$ROOT/.claude/workflow.env" ] && . "$ROOT/.claude/workflow.env"

MODEL="${2:-${WF_WORKER_MODEL:-cursor/composer-2.5}}"
REVIEW_MODEL="${3:-${WF_REVIEW_MODEL:-codex/deepseek-v4-flash}}"
REVIEW_MODEL_2="${4:-}"   # 双验收=按需 opt-in:planner 显式传第4参(通常 $WF_REVIEW_MODEL_STRONG)才触发;不从 env 自动读,免每单都双验

if [ "${REVIEW_ONLY:-0}" = "1" ] && [ "${SKIP_REVIEW:-0}" = "1" ]; then
  echo "✗ REVIEW_ONLY=1 与 SKIP_REVIEW=1 互斥,不能同时设置" >&2
  exit 1
fi

[ -f "$WO" ] || { echo "✗ 工单文件不存在: $WO" >&2; exit 1; }
command -v jq >/dev/null || { echo "✗ 找不到 jq(解析 token 用量需要)" >&2; exit 1; }

mkdir -p scratchpad/runs
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${STAMP}-$$"
RUN_DIR="scratchpad/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"
LOG="${RUN_DIR}/run.log"
REPORT_FILE="${RUN_DIR}/report.md"

# 前言从文件注入(单一来源,免 bash 转义;__TOKEN__ 由脚本替换运行期路径)
EXEC_TMPL="$(cat "$ROOT/.claude/skills/planner/worker-preamble.md")"
REVIEW_TMPL="$(cat "$ROOT/.claude/skills/planner/review-preamble.md")"
EXEC_PREAMBLE="${EXEC_TMPL//__REPORT_FILE__/$REPORT_FILE}"

# run_stage: 按「后端/模型」分派到对应 CLI。$1=标签 $2=后端/模型 $3=prompt → 回显 token,trace 只进 log
run_stage () {
  # 调用方已用 set +e 括住,这里不再动 errexit(内层 set -e 会泄漏到调用方,坑后续阶段)
  local label="$1" spec="$2" prompt="$3" backend model out rc usage
  case "$spec" in
    */*) backend="${spec%%/*}"; model="${spec#*/}" ;;
    *)   backend="cursor";       model="$spec" ;;   # 省前缀 = cursor(向后兼容)
  esac
  echo "── [$label] ${backend}:${model} ──" | tee -a "$LOG"
  case "$backend" in
    cursor)
      command -v cursor-agent >/dev/null || { echo "✗ 找不到 cursor-agent" >&2; return 2; }
      out="$(cursor-agent -p "$prompt" --model "$model" --force --trust --output-format json 2>>"$LOG")"
      rc=$?
      usage="$(printf '%s' "$out" | jq -rc '.usage // empty' 2>/dev/null || true)"
      ;;
    codex)
      command -v codex >/dev/null || { echo "✗ 找不到 codex" >&2; return 2; }
      out="$(printf '%s' "$prompt" | codex exec --dangerously-bypass-approvals-and-sandbox \
             -m "$model" -C "$ROOT" 2>>"$LOG")"
      rc=$?
      # codex plain 输出末尾有「tokens used\n<数字>」,取那个数字
      usage="$(printf '%s' "$out" | awk '/tokens used/{getline; gsub(/^ +/,""); print; exit}')"
      ;;
    *) echo "✗ 未知后端: $backend(只支持 cursor|codex)" >&2; return 2 ;;
  esac
  printf '%s\n' "$out" >>"$LOG"
  echo "  [$label] token 用量: ${usage:-见 log}" | tee -a "$LOG"
  return $rc
}

RO_LABEL=""
[ "${REVIEW_ONLY:-0}" = "1" ] && RO_LABEL="  (REVIEW_ONLY=1,跳过执行)"
{
  echo "▶ 派单     : $WO"
  echo "▶ 执行模型 : $MODEL${RO_LABEL}"
  if [ "${SKIP_REVIEW:-0}" = "1" ]; then
    echo "▶ 审查     : (跳过)"
  else
    echo "▶ 审查模型 : $REVIEW_MODEL${REVIEW_MODEL_2:+  +双验收 $REVIEW_MODEL_2}"
  fi
  echo "▶ 派单前   : HEAD $(git rev-parse --short HEAD) ($(git branch --show-current))"
  echo "▶ run 目录 : $RUN_DIR"
  echo "────────────────────────────────────────────────────────"
} | tee "$LOG"

set +e
# ① 执行
if [ "${REVIEW_ONLY:-0}" = "1" ]; then
  RC=0
  echo "── [执行] REVIEW_ONLY=1,跳过执行阶段 ──" | tee -a "$LOG"
else
  run_stage "执行" "$MODEL" "$(printf '%s\n\n%s\n' "$EXEC_PREAMBLE" "$(cat "$WO")")"
  RC=$?
fi

# ② 独立验收(可 1 或 2 个审查员;each 写自己的 review 文件)
REVIEW_MODELS=()
REVIEW_FILES=()
if [ "${SKIP_REVIEW:-0}" != "1" ]; then
  REVIEW_MODELS+=("$REVIEW_MODEL"); REVIEW_FILES+=("${RUN_DIR}/review.md")
  if [ -n "$REVIEW_MODEL_2" ]; then
    REVIEW_MODELS+=("$REVIEW_MODEL_2"); REVIEW_FILES+=("${RUN_DIR}/review2.md")
  fi
fi

REVIEW_ANY_NOGO=0
REVIEW_ANY_FAIL=""
REVIEW_RC_ECHO=""
REVIEW_NOGO_SUMMARY=""
for i in "${!REVIEW_MODELS[@]}"; do
  rm="${REVIEW_MODELS[$i]}"; rfile="${REVIEW_FILES[$i]}"
  preamble="${REVIEW_TMPL//__REVIEW_FILE__/$rfile}"
  run_stage "验收$((i+1))" "$rm" "$(printf '%s\n\n%s\n' "$preamble" "$(cat "$WO")")"
  rrc=$?
  REVIEW_RC_ECHO+="验收$((i+1))退出码: $rrc"$'\n'
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
