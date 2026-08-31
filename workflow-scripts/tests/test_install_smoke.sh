#!/usr/bin/env bash
# test_install_smoke.sh — install.sh 冒烟:装进临时 git repo,验投影 / exclude / pre-commit / seed 落位。
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$KIT_ROOT/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
_ok () { echo "✓ $1"; }
_no () { echo "✗ $1"; FAIL=$((FAIL + 1)); }

DEST="$TMP/proj"
mkdir -p "$DEST"
git init -q "$DEST"

"$INSTALL" "$DEST" >/dev/null 2>&1 || _no "install.sh 退出非零"

# 投影落位
[ -d "$DEST/.claude/skills" ]           && _ok ".claude/skills 投影"            || _no ".claude/skills 缺失"
[ -d "$DEST/scripts/workflow" ]         && _ok "scripts/workflow 投影"          || _no "scripts/workflow 缺失"
[ -f "$DEST/agent-discipline.md" ]      && _ok "agent-discipline.md 投影"       || _no "agent-discipline.md 缺失"
[ -f "$DEST/.claude/workflow.env.example" ] && _ok "workflow.env.example 投影" || _no "workflow.env.example 缺失"

# .git/info/exclude 忽略块
grep -qF "workflow-kit" "$DEST/.git/info/exclude" 2>/dev/null \
  && _ok ".git/info/exclude 有忽略块" || _no ".git/info/exclude 无忽略块"

# pre-commit
[ -x "$DEST/.git/hooks/pre-commit" ] && _ok "pre-commit 已装且可执行" || _no "pre-commit 未装/不可执行"

# seed
[ -f "$DEST/AGENTS.md" ]                    && _ok "AGENTS.md seed"              || _no "AGENTS.md 未 seed"
[ -f "$DEST/decisions/0000-template.md" ]  && _ok "decisions/0000-template seed" || _no "ADR 模板未 seed"
[ -e "$DEST/CLAUDE.md" ]                    && _ok "CLAUDE.md 软链"              || _no "CLAUDE.md 软链缺失"

# 幂等:二次装不炸、不重复写 exclude 块
"$INSTALL" "$DEST" >/dev/null 2>&1 || _no "install.sh 二次运行非零"
blocks="$(grep -cF "投影副本 + scratch,本地忽略" "$DEST/.git/info/exclude" 2>/dev/null || echo 0)"
[ "$blocks" = "1" ] && _ok "exclude 块幂等(仅一份)" || _no "exclude 块重复($blocks 份)"

[ "$FAIL" -eq 0 ]
