#!/usr/bin/env bash
# PreToolUse(Bash)钩子 —— 闸门3:派 run_worker.sh 前,检查工单顶部有「本单服务 → ADR-NNNN」意图行。
# 缺则 deny(见 WO-TEMPLATE 抬头 / /planner skill 闸门3):这行是给用户扫一眼拦跑偏用的。
#
# §0.2 不静默兜底:能明确判定「缺意图行」才拦;判不了的边界(拿不到工单参数 / 文件不存在)
#   **fail-open 放行,但打点自曝**(stderr 记一行,不静默),别把「查不了」伪装成「没问题」。
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

self_expose () {  # 打点自曝:fail-open 但留信号,不静默(§0.2)
  echo "check_wo_intent[闸门3][fail-open]: $1 —— 放行但未验证意图行,请人工留意" >&2
}

# 只在「把 run_worker.sh / rw.snap.sh 当命令跑、且后面紧跟 .md 工单参数」= 真派单时动作。
# 也认自举副本 rw.snap.sh(planner 自改脚本时从副本跑,见 /planner skill 自举纪律)。
# 仅「提到」脚本(bash -n / cp / cat / grep / 编辑它)或不带 .md → 不是派单,静默放行——
# 否则会误抓命令里任意一个无关 .md 当工单、假拦合法命令(dogfood 已踩:`cp …0000-template.md …` 被误判)。
dispatch="$(printf '%s' "$cmd" | grep -oE '(run_worker|rw\.snap)\.sh[[:space:]]+[^[:space:]]+\.md' | head -1)"
[ -n "$dispatch" ] || exit 0
wo="$(printf '%s' "$dispatch" | grep -oE '[^[:space:]]+\.md$')"
[ -n "$wo" ] || exit 0
[ -f "$wo" ] || { self_expose "工单文件不存在: $wo(run_worker 会自行报错)"; exit 0; }

# 明确判定:意图行须含「本单服务」且指向某个 ADR-NNNN。
intent="$(grep -m1 '本单服务' "$wo" || true)"
if [ -z "$intent" ]; then
  jq -n --arg wo "$wo" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("闸门3:工单 " + $wo + " 缺「本单服务 → ADR-NNNN」意图对齐行(见 WO-TEMPLATE 抬头)。补上再派——这行是给用户扫一眼拦跑偏用的。")
    }
  }'
  exit 0
fi
if ! printf '%s' "$intent" | grep -qE 'ADR-[0-9]{4}'; then
  jq -n --arg wo "$wo" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("闸门3:工单 " + $wo + " 的「本单服务」意图行未指向具体 ADR-NNNN。每张 WO 跟一个决策走(WO-<ADR>-<序号>),意图行须引 ADR-NNNN。")
    }
  }'
  exit 0
fi

# 有合规意图行 → 放行
exit 0
