#!/usr/bin/env bash
# test_install_smoke.sh — install.sh 冒烟:验 .workflow/ 投影布局、两模式 exclude 粒度、backend 矩阵、
#                          skills 软链入口、VERSION 印记、seed 落位、幂等。
set -uo pipefail

KIT_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"   # ai-workflow 仓根(kit/scripts/tests → 上溯 3 层)
INSTALL="$KIT_ROOT/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
_ok () { echo "✓ $1"; }
_no () { echo "✗ $1"; FAIL=$((FAIL + 1)); }

# ─────────── A. 默认(track)+ 默认 backend(cc)───────────
DEST="$TMP/track"
mkdir -p "$DEST"; git init -q "$DEST"
"$INSTALL" "$DEST" >/dev/null 2>&1 || _no "[track] install.sh 退出非零"

# 机制层落位
[ -d "$DEST/.workflow/kit/skills" ]                 && _ok "[track] .workflow/kit/skills"        || _no "[track] kit/skills 缺失"
[ -f "$DEST/.workflow/kit/scripts/run_worker.sh" ]  && _ok "[track] kit/scripts/run_worker.sh"   || _no "[track] kit/scripts 缺失"
[ -f "$DEST/.workflow/kit/discipline.md" ]         && _ok "[track] kit/discipline.md"          || _no "[track] discipline.md 缺失"
[ -f "$DEST/.workflow/kit/settings.json" ]          && _ok "[track] kit/settings.json"           || _no "[track] settings.json 缺失"
[ -f "$DEST/.workflow/kit/workflow.env.example" ]   && _ok "[track] kit/workflow.env.example"    || _no "[track] workflow.env.example 缺失"

# VERSION 印记
grep -q '^ai-workflow ' "$DEST/.workflow/VERSION" 2>/dev/null && _ok "[track] VERSION 印记" || _no "[track] VERSION 缺失/格式错"

# 设计资产 seed
[ -f "$DEST/.workflow/decisions/0000-template.md" ] && _ok "[track] decisions/0000-template seed" || _no "[track] ADR 模板未 seed"
[ -f "$DEST/AGENTS.md" ]                             && _ok "[track] AGENTS.md seed(仓根)"       || _no "[track] AGENTS.md 未 seed"

# CLAUDE.md = 一行 @AGENTS.md(非软链)
[ ! -L "$DEST/CLAUDE.md" ] && [ "$(cat "$DEST/CLAUDE.md" 2>/dev/null)" = "@AGENTS.md" ] \
  && _ok "[track] CLAUDE.md = @AGENTS.md(非软链)" || _no "[track] CLAUDE.md 非预期"

# cc 后端:.claude/skills 软链 → kit/skills
[ -L "$DEST/.claude/skills" ] && [ -d "$DEST/.claude/skills/planner" ] \
  && _ok "[track] .claude/skills 软链解析到真源" || _no "[track] .claude/skills 软链失效"
[ -f "$DEST/.claude/settings.json" ] && _ok "[track] .claude/settings.json 暴露" || _no "[track] .claude/settings.json 缺失"

# track 粒度 exclude:排机制层,不排 decisions
grep -qF "/.workflow/kit/" "$DEST/.git/info/exclude"    && _ok "[track] exclude 收 /.workflow/kit/"    || _no "[track] exclude 未收 kit"
grep -qxF "/.workflow/decisions/" "$DEST/.git/info/exclude" && _no "[track] exclude 误排 decisions" || _ok "[track] exclude 不排 decisions"
grep -qxF "/.workflow/" "$DEST/.git/info/exclude" && _no "[track] track 模式不应整包排 .workflow" || _ok "[track] track 不整包排 .workflow"

# pre-commit
[ -x "$DEST/.git/hooks/pre-commit" ] && _ok "[track] pre-commit 已装且可执行" || _no "[track] pre-commit 未装"

# 幂等:二次装不炸、exclude 块仅一份
"$INSTALL" "$DEST" >/dev/null 2>&1 || _no "[track] install.sh 二次运行非零"
blocks="$(grep -cF ".workflow 投影 + 后端入口" "$DEST/.git/info/exclude" 2>/dev/null || echo 0)"
[ "$blocks" = "1" ] && _ok "[track] exclude 块幂等(仅一份)" || _no "[track] exclude 块重复($blocks 份)"

# ─────────── B. no-track ───────────
DEST2="$TMP/notrack"
mkdir -p "$DEST2"; git init -q "$DEST2"
"$INSTALL" --no-track "$DEST2" >/dev/null 2>&1 || _no "[no-track] install.sh 退出非零"
grep -qxF "/.workflow/" "$DEST2/.git/info/exclude" && _ok "[no-track] exclude 整包收 /.workflow/" || _no "[no-track] 未整包排 .workflow"
grep -qxF "/AGENTS.md" "$DEST2/.git/info/exclude"  && _ok "[no-track] exclude 收 /AGENTS.md"       || _no "[no-track] 未排 AGENTS.md"
grep -qxF "/CLAUDE.md" "$DEST2/.git/info/exclude"  && _ok "[no-track] exclude 收 /CLAUDE.md"       || _no "[no-track] 未排 CLAUDE.md"

# ─────────── C. backend 矩阵:cc,codex ───────────
DEST3="$TMP/multi"
mkdir -p "$DEST3"; git init -q "$DEST3"
"$INSTALL" --backends cc,codex "$DEST3" >/dev/null 2>&1 || _no "[cc,codex] install.sh 退出非零"
[ -L "$DEST3/.claude/skills" ] && [ -d "$DEST3/.claude/skills/planner" ] && _ok "[cc,codex] .claude/skills 软链" || _no "[cc,codex] .claude/skills 失效"
[ -L "$DEST3/.agents/skills" ] && [ -d "$DEST3/.agents/skills/planner" ] && _ok "[cc,codex] .agents/skills 软链" || _no "[cc,codex] .agents/skills 失效"
grep -qxF "/.agents/" "$DEST3/.git/info/exclude" && _ok "[cc,codex] exclude 收 /.agents/" || _no "[cc,codex] 未排 .agents"

# ─────────── D. 切模式 exclude 刷新(#2 回归:track→no-track 重装必须改粒度,不 stale)───────────
"$INSTALL" --no-track "$DEST" >/dev/null 2>&1 || _no "[switch] track→no-track 重装非零"
grep -qxF "/.workflow/" "$DEST/.git/info/exclude"        && _ok "[switch] 重装后转 no-track 粒度(整包排)" || _no "[switch] 未刷新到 no-track"
grep -qxF "/.workflow/kit/" "$DEST/.git/info/exclude"    && _no "[switch] 仍残留 track 粒度(stale)"       || _ok "[switch] track-only 行已清除"
blocks2="$(grep -cF ".workflow 投影 + 后端入口" "$DEST/.git/info/exclude" 2>/dev/null || echo 0)"
[ "$blocks2" = "1" ] && _ok "[switch] 切模式后仍仅一份块" || _no "[switch] 块数异常($blocks2)"

[ "$FAIL" -eq 0 ]
