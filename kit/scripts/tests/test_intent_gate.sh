#!/usr/bin/env bash
# 派单真实入口的目标检查；不调用模型。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KIT_RW="$SCRIPT_DIR/run_worker.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git init -q "$TMP/repo"
cd "$TMP/repo"

check () {
  local expected="$1" label="$2" body="$3" rc=0
  printf '%s' "$body" > "$TMP/brief.md"
  RUN_WORKER_INTENT_CHECK_ONLY=1 "$KIT_RW" "$TMP/brief.md" >"$TMP/output" 2>&1 || rc=$?
  if { [ "$expected" = accept ] && [ "$rc" -eq 0 ]; } ||
     { [ "$expected" = reject ] && [ "$rc" -ne 0 ] && grep -q '需要非空' "$TMP/output"; }; then
    echo "✓ $label"
  else
    echo "✗ $label (rc=$rc)"
    cat "$TMP/output"
    exit 1
  fi
}

check accept '旧 ADR 工单可派' $'# 工单\n- **本单服务 → ADR-0007 的意图**: 校验响应格式\n'
check accept '无 ADR 的用户目标可派' $'# 局部修复\n目标：修复空输入时的异常\n'
check accept '英文冒号与 Markdown 目标可派' $'- **目标:** 调查实际请求的字段\r\n'
check reject '缺目标不能派，且确实由目标检查拒绝' $'# 工单\n只列文件名\n'
check reject '空目标不能派' $'目标：  \r\n依据：用户任务\n'
check reject '仅 Markdown 标记的目标不能派' $'**目标:** **  **\n'
check reject '空的旧 ADR 意图不能派' $'本单服务 → ADR-0007 的意图: \n'
check reject '正文中提到目标不冒充目标行' $'请检查目标：是否合理\n'
check reject '尖括号占位符目标不能派' $'目标：<要实现的行为或需要回答的问题>\n'
check reject '未填 WO 模板不能派' "$(cat "$SCRIPT_DIR/../skills/planner/WO-TEMPLATE.md")"
check accept '目标中含尖括号字段名仍可派' $'目标：修复 <input> 为空时的异常\n'

if grep -E 'check_wo_intent|doc_guard' "$SCRIPT_DIR/../settings.json" >/dev/null 2>&1; then
  echo '✗ settings.json 仍引用废弃 hook 条目'
  exit 1
fi
echo '✓ settings.json 无 check_wo_intent/doc_guard'

[ ! -d scratchpad/runs ]
echo '✓ 仅校验入口不产生 run 或外呼'
