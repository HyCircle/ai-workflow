#!/usr/bin/env bash
# workflow-kit/install.sh — 把工作流机制装进一个目标项目。
# 用法: /path/to/workflow-kit/install.sh [目标项目根,默认当前目录]
# 装什么:.claude/{skills,hooks,settings.json,workflow.env.example} + scripts/workflow/*.{py,sh}
#         + 首次 seed AGENTS.md(+CLAUDE.md 软链)、decisions/0000-template.md(已存在则不覆盖)。
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
[ -f "$DEST/AGENTS.md" ]                  || cp "$KIT/seed/AGENTS.md" "$DEST/AGENTS.md"
[ -e "$DEST/CLAUDE.md" ]                  || ln -s AGENTS.md "$DEST/CLAUDE.md" 2>/dev/null || echo "⚠ 未能建 CLAUDE.md 软链(Windows?)——请手动让 CLAUDE.md 指向 AGENTS.md"
[ -f "$DEST/decisions/0000-template.md" ] || { mkdir -p "$DEST/decisions"; cp "$KIT/seed/decisions/0000-template.md" "$DEST/decisions/"; }
# 注:workflow.md 是维护者蓝图,常驻 workflow-kit/workflow.md,不 seed 进消费项目(agent 不读它)。

cat <<EOF
✓ 已装入 $DEST
下一步:
  1) cd "$DEST" && cp .claude/workflow.env.example .claude/workflow.env   # 填模型/命令档
     并在 AGENTS.md「项目工具约定」填本项目技术栈
  2) 确认目标 .gitignore 忽略 .claude/ 与 scripts/workflow/(它们是本机安装副本)
  3) 重启 Claude Code —— 首次会提示信任新 hooks,批准即生效
EOF
