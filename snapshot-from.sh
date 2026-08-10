#!/usr/bin/env bash
# workflow-kit/snapshot-from.sh — 反向:把某项目 live 的机制回抓进本 kit(tracked 快照)。
# 用于「trial 期直接改了 live 的 .claude / scripts/workflow 后」更新 kit,再 git 提交。
# 用法: /path/to/workflow-kit/snapshot-from.sh [源项目根,默认当前目录]
# 注:只抓 workflow.env.example,绝不抓 live workflow.env(每机私有值)。
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$(pwd)}"
[ -d "$SRC/.claude/skills" ] || { echo "✗ 源项目无 .claude/skills: $SRC" >&2; exit 1; }

rm -rf "$KIT/claude/skills" "$KIT/claude/hooks"
cp -r "$SRC/.claude/skills" "$KIT/claude/"
cp -r "$SRC/.claude/hooks"  "$KIT/claude/"
cp "$SRC/.claude/settings.json"        "$KIT/claude/settings.json"
cp "$SRC/.claude/workflow.env.example" "$KIT/claude/workflow.env.example"
mkdir -p "$KIT/workflow-scripts"
cp "$SRC/scripts/workflow/"*.py "$SRC/scripts/workflow/"*.sh "$KIT/workflow-scripts/"
[ -f "$SRC/decisions/0000-template.md" ] && cp "$SRC/decisions/0000-template.md" "$KIT/seed/decisions/"
[ -f "$SRC/docs/workflow.md" ]           && cp "$SRC/docs/workflow.md" "$KIT/seed/docs/"
find "$KIT" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
echo "✓ 已从 $SRC 快照进 kit。检查 git diff workflow-kit/ 后提交。"
