#!/usr/bin/env bash
# workflow-kit/install.sh — 把工作流机制装进一个目标项目。
# 用法: /path/to/workflow-kit/install.sh [目标项目根,默认当前目录]
# 装什么:.claude/{skills,hooks,settings.json,workflow.env.example} + scripts/workflow/*.{py,sh}
#         + 首次 seed decisions/0000-template.md、docs/workflow.md(已存在则不覆盖)。
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$(pwd)}"
[ -d "$DEST" ] || { echo "✗ 目标不存在: $DEST" >&2; exit 1; }

mkdir -p "$DEST/.claude" "$DEST/scripts/workflow"
cp -r "$KIT/claude/skills" "$DEST/.claude/"
cp -r "$KIT/claude/hooks"  "$DEST/.claude/"
cp "$KIT/claude/workflow.env.example" "$DEST/.claude/workflow.env.example"
cp "$KIT/workflow-scripts/"*.py "$KIT/workflow-scripts/"*.sh "$DEST/scripts/workflow/"

# settings.json:已存在则不覆盖(可能有别的配置),提示手动并 hooks
if [ -f "$DEST/.claude/settings.json" ]; then
  echo "⚠ 已存在 $DEST/.claude/settings.json —— 未覆盖。请手动并入 hooks(参照 $KIT/claude/settings.json)。"
else
  cp "$KIT/claude/settings.json" "$DEST/.claude/settings.json"
fi

# 文档系统 seed:仅当缺失时补,不覆盖既有
[ -f "$DEST/decisions/0000-template.md" ] || { mkdir -p "$DEST/decisions"; cp "$KIT/seed/decisions/0000-template.md" "$DEST/decisions/"; }
[ -f "$DEST/docs/workflow.md" ]           || { mkdir -p "$DEST/docs";      cp "$KIT/seed/docs/workflow.md" "$DEST/docs/"; }

cat <<EOF
✓ 已装入 $DEST
下一步:
  1) cd "$DEST" && cp .claude/workflow.env.example .claude/workflow.env   # 填模型/命令档
  2) 确认目标 .gitignore 忽略 .claude/ 与 scripts/workflow/(它们是本机安装副本)
  3) 重启 Claude Code —— 首次会提示信任新 hooks,批准即生效
EOF
