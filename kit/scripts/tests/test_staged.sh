#!/usr/bin/env bash
# test_staged.sh — check_docs --staged 读 index blob 而非工作树。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DOCS_SRC="$SCRIPT_DIR/check_docs.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git init "$TMP/repo" >/dev/null 2>&1
cd "$TMP/repo"
git config user.email "t@test" && git config user.name "t"
# 新布局:check_docs 在 .workflow/kit/scripts,ADR 在 .workflow/decisions(测 _workflow_dir 的 .workflow 分支)。
mkdir -p .workflow/kit/scripts .workflow/decisions
cp "$CHECK_DOCS_SRC" .workflow/kit/scripts/check_docs.py
CD=".workflow/kit/scripts/check_docs.py"

cat > .workflow/decisions/0001-bad.md <<'EOF'
# 无 frontmatter 的坏 ADR
body
EOF
git add -f .workflow/decisions/0001-bad.md

# 工作树改成合法,但 staged 仍是坏的
cat > .workflow/decisions/0001-bad.md <<'EOF'
---
id: "0001"
status: accepted
---
# ok
EOF

if ${WF_PY:-uv run python} "$CD" --staged >/dev/null 2>&1; then
  echo "✗ staged 非法 ADR 应非零"
  exit 1
fi
echo "✓ staged 非法(工作树合法) → 非零"

git add -f .workflow/decisions/0001-bad.md
if ${WF_PY:-uv run python} "$CD" --staged >/dev/null 2>&1; then
  echo "✓ staged 合法 → 0"
else
  echo "✗ staged 合法应退出 0"
  exit 1
fi
