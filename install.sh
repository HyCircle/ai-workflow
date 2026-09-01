#!/usr/bin/env bash
# install.sh — 把工作流机制装进 / 更新一个目标仓,全部收进 <gitroot>/.workflow/(统一投影布局)。
# 用法: /path/to/ai-workflow/install.sh [--track|--no-track] [--backends cc,codex,cursor] [目标仓根,默认当前目录]
#
#   --track     (默认)  设计资产(decisions/ architecture.md TODO.md VERSION)版本化;exclude 只收机制层 +
#                        本机配置 + scratch(/.workflow/kit/ /.workflow/workflow.env /.workflow/scratchpad/)。
#   --no-track           整个 /.workflow/ + 根发现文档(AGENTS.md CLAUDE.md)全 exclude,不版本化(ADR 易失,
#                        用户已接受;适合生产/消费仓与工作流命名空间隔离)。
#   --backends  csv      建哪些后端根入口(cc→.claude、codex→.agents、cursor 蹭别人不单建)。默认 cc。
#
# 装什么:.workflow/kit/(机制 copy 快照) + .workflow/{decisions,VERSION}(设计资产 seed) + 根 AGENTS.md/CLAUDE.md
#         + 后端入口(skills 真源一份 = .workflow/kit/skills,给只认自家目录的后端各建软链入口)
#         + git pre-commit(校验待提交文档结构)。
# 忽略项写进目标 .git/info/exclude(本地、不碰 tracked .gitignore),装进已有项目零改其版本库。
# 升级 = 按需重跑本脚本(只 copy kit 快照 + 刷 VERSION;设计资产/本机配置永不覆盖)。
set -euo pipefail
KIT_SRC="$(cd "$(dirname "$0")" && pwd)"   # ai-workflow 仓根(本脚本所在)
SRC_KIT="$KIT_SRC/kit"                      # 机制 SOT

TRACK=1
BACKENDS="cc"
DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --track)       TRACK=1 ;;
    --no-track)    TRACK=0 ;;
    --backends)    shift; BACKENDS="${1:?--backends 需一个逗号分隔值,如 cc,codex}" ;;
    --backends=*)  BACKENDS="${1#--backends=}" ;;
    -*)            echo "✗ 未知选项: $1" >&2; exit 1 ;;
    *)             DEST="$1" ;;
  esac
  shift
done
DEST="${DEST:-$(pwd)}"
[ -d "$DEST" ] || { echo "✗ 目标不存在: $DEST" >&2; exit 1; }
[ -d "$SRC_KIT" ] || { echo "✗ 机制源缺失: $SRC_KIT(本脚本须在 ai-workflow 仓内)" >&2; exit 1; }

# 后端解析
HAS_CC=0; HAS_CODEX=0; HAS_CURSOR=0
IFS=',' read -ra _bk <<< "$BACKENDS"
for b in "${_bk[@]}"; do
  case "$b" in
    cc)     HAS_CC=1 ;;
    codex)  HAS_CODEX=1 ;;
    cursor) HAS_CURSOR=1 ;;
    "")     ;;
    *)      echo "✗ 未知后端: $b(支持 cc|codex|cursor)" >&2; exit 1 ;;
  esac
done

WF="$DEST/.workflow"

# ── 1. 机制层:整个 kit copy 进 .workflow/kit(升级即覆盖;设计资产在 kit 外,不受影响)──
mkdir -p "$WF"
rm -rf "$WF/kit"
cp -r "$SRC_KIT" "$WF/kit"

# ── 2. VERSION 印记:装了哪版 ai-workflow ──
VER_TAG="$(git -C "$KIT_SRC" describe --tags --always 2>/dev/null || echo unknown)"
VER_COMMIT="$(git -C "$KIT_SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
{
  echo "ai-workflow $VER_TAG"
  echo "commit $VER_COMMIT"
  echo "installed $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$WF/VERSION"

# ── 3. 设计资产 seed(首次;已存在不覆盖)──
if [ ! -f "$WF/decisions/0000-template.md" ]; then
  mkdir -p "$WF/decisions"
  cp "$KIT_SRC/seed/decisions/0000-template.md" "$WF/decisions/"
fi

# 根发现文档:AGENTS.md = 唯一全文真源(留仓根);CLAUDE.md = 一行 @AGENTS.md(CC import,不再软链)。
if [ -f "$DEST/AGENTS.md" ]; then
  grep -q 'agent-discipline' "$DEST/AGENTS.md" || \
    echo "⚠ $DEST/AGENTS.md 已存在但未引用 agent-discipline —— 请在顶部加一行指向 .workflow/kit/agent-discipline.md"
else
  cp "$KIT_SRC/seed/AGENTS.md" "$DEST/AGENTS.md"
fi
[ -L "$DEST/CLAUDE.md" ] && rm -f "$DEST/CLAUDE.md"          # 迁移:旧布局的 CLAUDE.md→AGENTS.md 软链换成 import 行
[ -e "$DEST/CLAUDE.md" ] || printf '@AGENTS.md\n' > "$DEST/CLAUDE.md"

# ── 4. 后端入口:skills 真源一份 = .workflow/kit/skills;给只认自家目录的后端各建软链入口(相对链,可移植)──
_skills_entry () {   # $1 = 根入口目录名(.claude / .agents)
  local dir="$DEST/$1"
  mkdir -p "$dir"
  rm -rf "$dir/skills"
  ln -s "../.workflow/kit/skills" "$dir/skills"
}
[ "$HAS_CC" = "1" ] && _skills_entry ".claude"
[ "$HAS_CODEX" = "1" ] && _skills_entry ".agents"
# cursor 全能(蹭 .claude/.agents/.codex);仅当它是唯一后端才借 .claude/skills 给它读。
BORROW_CLAUDE=0
if [ "$HAS_CURSOR" = "1" ] && [ "$HAS_CC" = "0" ] && [ "$HAS_CODEX" = "0" ]; then
  _skills_entry ".claude"; BORROW_CLAUDE=1
fi
# CC 的 settings.json:入口暴露一份(首次;已存在不覆盖,可能有别的配置)
if [ "$HAS_CC" = "1" ]; then
  if [ -f "$DEST/.claude/settings.json" ]; then
    grep -qE 'check_wo_intent|doc_guard' "$DEST/.claude/settings.json" && \
      echo "  ↳ 请从 .claude/settings.json 删掉 check_wo_intent / doc_guard 条目(闸门已在派单脚本)。"
  else
    mkdir -p "$DEST/.claude"
    cp "$WF/kit/settings.json" "$DEST/.claude/settings.json"
  fi
fi

# ── 5. 旧布局残留清理(从散落投影迁移到 .workflow/ 时;都是 kit 独占命名,安全删)──
rm -f  "$DEST/agent-discipline.md" "$DEST/.claude/workflow.env.example"
rm -rf "$DEST/scripts/workflow"; rmdir "$DEST/scripts" 2>/dev/null || true
rm -f  "$DEST/.claude/hooks/check_wo_intent.sh" "$DEST/.claude/hooks/doc_guard.sh"
rmdir  "$DEST/.claude/hooks" 2>/dev/null || true

# ── 6. .git/info/exclude(BEGIN/END 界定 + 每次重写)+ pre-commit ──
# 每次先删旧块再写当前块 → exclude 始终反映本次 --track/--no-track 与 --backends(切模式重装即刷新粒度)。
if [ -d "$DEST/.git" ]; then
  EXCLUDE="$DEST/.git/info/exclude"
  BEGIN="# —— ai-workflow BEGIN(.workflow 投影 + 后端入口,本地忽略;install 生成,勿手改)——"
  END="# —— ai-workflow END ——"
  mkdir -p "$DEST/.git/info"; touch "$EXCLUDE"
  # 删本工具的旧块(BEGIN..END,# 作 sed 分隔符避开路径里的 /),再写当前块
  sed -i '\#ai-workflow BEGIN#,\#ai-workflow END#d' "$EXCLUDE"
  {
    echo "$BEGIN"
    if [ "$TRACK" = "1" ]; then
      # 精确排机制层 + 本机配置 + scratch;设计资产(decisions/ architecture.md TODO.md VERSION)tracked。
      # 注:gitignore 语法父目录整体排除后子文件 `!` 救不回,故必须精确排 /.workflow/kit/ 这一层。
      echo "/.workflow/kit/"
      echo "/.workflow/workflow.env"
      echo "/.workflow/scratchpad/"
    else
      # 整个 .workflow/ + 根发现文档全排(不版本化)。
      echo "/.workflow/"
      echo "/AGENTS.md"
      echo "/CLAUDE.md"
    fi
    { [ "$HAS_CC" = "1" ] || [ "$BORROW_CLAUDE" = "1" ]; } && echo "/.claude/"
    [ "$HAS_CODEX" = "1" ] && echo "/.agents/"
    [ "$HAS_CURSOR" = "1" ] && echo "/.cursor/"
    echo "$END"
  } >> "$EXCLUDE"
  echo "✓ 忽略项写进 .git/info/exclude($([ "$TRACK" = "1" ] && echo track || echo no-track) 粒度 · backends: $BACKENDS,每次重写、未碰 tracked .gitignore)"

  HOOK_DEST="$DEST/.git/hooks/pre-commit"
  if [ -f "$HOOK_DEST" ]; then
    echo "⚠ 已存在 $HOOK_DEST —— 未覆盖 pre-commit。请手动并入 $WF/kit/git-hooks/pre-commit。"
  else
    cp "$WF/kit/git-hooks/pre-commit" "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
    echo "✓ 已安装 git pre-commit → $HOOK_DEST"
  fi
else
  echo "⚠ 目标非 git 仓 —— 跳过 .git/info/exclude 与 pre-commit。init 后重跑本脚本。"
fi

cat <<EOF

✓ 已装入 $DEST(布局根 .workflow/,$([ "$TRACK" = "1" ] && echo "track" || echo "no-track") · backends: $BACKENDS)
  VERSION: $(head -1 "$WF/VERSION")
下一步:
  1) cd "$DEST" && cp .workflow/kit/workflow.env.example .workflow/workflow.env   # 填模型/命令档
     并在 AGENTS.md「项目工具约定」填本项目技术栈
  2) 忽略项已进 .git/info/exclude;闸门在派单脚本 + git pre-commit,无需 Claude Code hook
  3) 升级机制:改 ai-workflow/ → 重跑本脚本(只刷 .workflow/kit + VERSION,设计资产/配置不动)
EOF
