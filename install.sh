#!/usr/bin/env bash
# workflow-kit/install.sh — 把工作流机制装进 / 更新一个目标项目。
# 用法: /path/to/workflow-kit/install.sh [--link] [目标项目根,默认当前目录]
#   --link : symlink 共读(项目目录指向 kit 单源,改 kit 即时生效、免重装)。省略 = copy(冻结快照,Windows 稳)。
# 装什么:.claude/{skills,settings.json,workflow.env.example} + scripts/workflow/* + agent-discipline.md(六条纪律)
#         + git pre-commit(校验待提交文档结构)+ 首次 seed AGENTS.md(+CLAUDE.md 软链)、decisions/0000-template.md。
# 忽略项写进目标 **.git/info/exclude**(本地、不碰目标 tracked 的 .gitignore),故装进已有项目零改其版本库。
# 闸门下沉进脚本 + git pre-commit,不装 Claude Code 专属 hook。
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"

LINK=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --link) LINK=1 ;;
    *) DEST="$arg" ;;
  esac
done
DEST="${DEST:-$(pwd)}"
[ -d "$DEST" ] || { echo "✗ 目标不存在: $DEST" >&2; exit 1; }

# 投影一个文件/目录:link 模式 symlink 到 kit 单源,否则 copy。先清旧目标保证干净(避免 symlink 套进旧目录)。
_project () {
  local src="$1" dst="$2"
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  if [ "$LINK" = "1" ]; then
    ln -s "$src" "$dst"
  else
    cp -r "$src" "$dst"
  fi
}

mkdir -p "$DEST/.claude" "$DEST/scripts"
_project "$KIT/claude/skills"       "$DEST/.claude/skills"
_project "$KIT/workflow-scripts"    "$DEST/scripts/workflow"
_project "$KIT/agent-discipline.md" "$DEST/agent-discipline.md"
cp "$KIT/claude/workflow.env.example" "$DEST/.claude/workflow.env.example"

# 摘除已下沉进脚本的旧 Claude Code hook(更新既有安装时)
rm -f "$DEST/.claude/hooks/check_wo_intent.sh" "$DEST/.claude/hooks/doc_guard.sh"
rmdir "$DEST/.claude/hooks" 2>/dev/null || true

# 忽略项 → 目标 .git/info/exclude(幂等,不碰 tracked .gitignore)
if [ -d "$DEST/.git" ]; then
  EXCLUDE="$DEST/.git/info/exclude"
  MARKER="# —— workflow-kit(投影副本 + scratch,本地忽略)——"
  mkdir -p "$DEST/.git/info"
  if ! grep -qF "$MARKER" "$EXCLUDE" 2>/dev/null; then
    # 全部**根锚定**(前导 /):否则 `agent-discipline.md` 会连 kit 自己的
    # workflow-kit/agent-discipline.md(SOT,须 tracked)一起忽略掉。
    # `scripts/workflow` **不带尾 /**:--link 模式它是 symlink(git 当文件看),尾 / 的目录模式匹配不到。
    {
      echo ""
      echo "$MARKER"
      echo "/.claude/"
      echo "/scripts/workflow"
      echo "/agent-discipline.md"
      echo "/.cursor/"
      echo "/.codex/"
      echo "/scratchpad/"
    } >> "$EXCLUDE"
    echo "✓ 忽略项写进 .git/info/exclude(未碰 tracked .gitignore)"
  else
    echo "✓ .git/info/exclude 已有 workflow-kit 忽略块"
  fi

  # git pre-commit:已存在则不覆盖
  HOOK_DEST="$DEST/.git/hooks/pre-commit"
  if [ -f "$HOOK_DEST" ]; then
    echo "⚠ 已存在 $HOOK_DEST —— 未覆盖 pre-commit。请手动并入 $KIT/git-hooks/pre-commit。"
  else
    cp "$KIT/git-hooks/pre-commit" "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
    echo "✓ 已安装 git pre-commit → $HOOK_DEST"
  fi
else
  echo "⚠ 目标非 git 仓 —— 跳过 .git/info/exclude 与 pre-commit。init 后重跑本脚本。"
fi

# settings.json:已存在则不覆盖(可能有别的配置)
if [ -f "$DEST/.claude/settings.json" ]; then
  echo "⚠ 已存在 $DEST/.claude/settings.json —— 未覆盖。"
  if grep -qE 'check_wo_intent|doc_guard' "$DEST/.claude/settings.json"; then
    echo "  ↳ 检测到旧 hook 注册(check_wo_intent/doc_guard),请手动删掉这两条(闸门已下沉进脚本)。"
  fi
else
  cp "$KIT/claude/settings.json" "$DEST/.claude/settings.json"
fi

# 文档系统 seed:AGENTS.md 缺则 seed(shell:工具约定+地图+指向 discipline);已存在则不覆盖,只提示补指针。
if [ -f "$DEST/AGENTS.md" ]; then
  if ! grep -q 'agent-discipline.md' "$DEST/AGENTS.md"; then
    echo "⚠ $DEST/AGENTS.md 已存在但未引用 agent-discipline.md —— 请在其顶部加一行(六条纪律的家):"
    echo "   > 进项目先读 \`agent-discipline.md\`(工作流常驻六条纪律,kit 维护、勿改),再读本文件。"
  fi
else
  cp "$KIT/seed/AGENTS.md" "$DEST/AGENTS.md"
fi
[ -e "$DEST/CLAUDE.md" ]                  || ln -s AGENTS.md "$DEST/CLAUDE.md" 2>/dev/null || echo "⚠ 未能建 CLAUDE.md 软链(Windows?)——请手动让 CLAUDE.md 指向 AGENTS.md"
[ -f "$DEST/decisions/0000-template.md" ] || { mkdir -p "$DEST/decisions"; cp "$KIT/seed/decisions/0000-template.md" "$DEST/decisions/"; }
# 注:workflow.md 是维护者蓝图,常驻 workflow-kit/,不 seed 进消费项目(agent 不读它)。

cat <<EOF

✓ 已装入 $DEST ($([ "$LINK" = "1" ] && echo "symlink 共读" || echo "copy 快照"))
下一步:
  1) cd "$DEST" && cp .claude/workflow.env.example .claude/workflow.env   # 填模型/命令档
     并在 AGENTS.md「项目工具约定」填本项目技术栈
  2) 忽略项已进 .git/info/exclude;闸门在派单脚本 + git pre-commit 里,无需 Claude Code hook
  3) 更新机制:改 workflow-kit/ → copy 模式重跑本脚本推项目;--link 模式改 kit 即时生效、免重跑
EOF
