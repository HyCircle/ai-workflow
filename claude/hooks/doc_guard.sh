#!/usr/bin/env bash
# PostToolUse(Edit|Write)钩子 —— 文档结构守护:改任意 *.md 后自动跑 check_docs --changed,
# 有 ADR 结构违规 / ADR-NNNN 断链就注入警告(非阻塞,Claude 自行判定修不修)。
# 补 run_worker.sh 只覆盖 worker 路径、管不到 planner/bs 直接改文档(ADR/architecture/TODO)的空白。
# check_docs 已按新结构:认 ADR frontmatter(id/status)+ ADR-NNNN 断链;STATE 规则已删。
set -uo pipefail

input="$(cat)"
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

# 只关心 markdown
case "$fp" in
  *.md) ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# 单一配置源:WF_PY 等命令读 .claude/workflow.env(与 run_worker.sh 一致);缺文件退回内置默认。
[ -f "$root/.claude/workflow.env" ] && . "$root/.claude/workflow.env"
out="$(cd "$root" && ${WF_PY:-uv run python} scripts/workflow/check_docs.py --changed 2>&1)" || true

# 只在真有违规(输出含 ✗)时注入,避免把基础设施错误当违规
printf '%s' "$out" | grep -q '✗' || exit 0

jq -n --arg out "$out" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("文档结构守护(check_docs --changed)报问题:\n" + $out + "\n(自行判定修不修;ADR 结构/断链只认此脚本,别手写 grep)")
  }
}'
exit 0
