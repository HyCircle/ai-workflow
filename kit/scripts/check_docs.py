#!/usr/bin/env python3
"""文档结构守护(canonical)—— ADR frontmatter/命名校验 + `ADR-NNNN` 断链检查。

决策活在 `.workflow/decisions/NNNN-slug.md`,引用写 `ADR-NNNN`,断链 = 查 `.workflow/decisions/NNNN-*` 在不在。

**为什么用脚本不用手写 grep**:手写 `grep 'ADR-[0-9]'` 会因空格/子串/注释误报,
分不清「本轮引入」与「存量」。脚本 = 唯一真相:正则精确、按结构化 frontmatter 校验、
可选 `--changed` 只看本轮改动。

用法:
    uv run python .workflow/kit/scripts/check_docs.py            # 全仓
    uv run python .workflow/kit/scripts/check_docs.py --changed  # 只检本轮 git 改动(验收用)
    uv run python .workflow/kit/scripts/check_docs.py --staged   # 只检 index 待提交 blob(pre-commit 用)

退出码:有违规 → 1,干净 → 0。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

def _repo_root() -> Path:
    """消费项目的仓根 = git toplevel(按 cwd)。**不用 `__file__` parents**:symlink 共读时
    本文件的真身在外部 kit repo,parents 会解析进 kit 而非消费项目,扫错仓。git toplevel 按
    调用者 cwd(run_worker / pre-commit 都已 cd 进消费仓),symlink 与否都对。"""
    r = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if r.returncode != 0 or not r.stdout.strip():
        raise SystemExit("✗ check_docs 须在 git 仓库内运行")
    return Path(r.stdout.strip())


def _workflow_dir(root: Path) -> Path:
    """布局根:消费仓 = `<gitroot>/.workflow/`(约定优于配置);kit 自研仓无 `.workflow/` → 退回 gitroot。
    设计资产(decisions/architecture.md/TODO.md)的家,位置固定在此。"""
    wf = root / ".workflow"
    return wf if wf.is_dir() else root


ROOT = _repo_root()
WF = _workflow_dir(ROOT)
DECISIONS = WF / "decisions"

VALID_STATUS = frozenset({"proposed", "accepted", "superseded", "deprecated"})

# ADR 文件名/引用:NNNN = 四位数字。
_FILENAME_RE = re.compile(r"^(\d{4})-[a-z0-9][a-z0-9-]*$")  # NNNN-kebab-slug(不含 .md)
_REF_RE = re.compile(r"ADR-(\d{4})")                        # 代码/文档里的引用 token
_ID_RE = re.compile(r"^id:\s*['\"]?(\d{1,4})['\"]?\s*$")
_STATUS_RE = re.compile(r"^status:\s*([a-z]+)")

# 扫 `ADR-NNNN` 引用的文本后缀(scratchpad 已 gitignore,不入扫描)。
_REF_SUFFIXES = frozenset({".py", ".md", ".ts", ".tsx", ".js", ".rs", ".toml", ".sh"})


def _is_adr_stem(stem: str) -> bool:
    """NNNN-slug 且非模板(0000-template 是脚手架,不算 ADR)。"""
    return bool(_FILENAME_RE.match(stem)) and not stem.endswith("-template")


def _git_lines(args: list[str]) -> list[str]:
    res = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    return [ln for ln in res.stdout.splitlines() if ln.strip()]


def _repo_text_files() -> list[Path]:
    """仓内文本文件(tracked + untracked-非忽略),按后缀过滤。gitignore 自动排除 scratchpad。"""
    seen: set[Path] = set()
    for args in (
        ["git", "ls-files"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        for line in _git_lines(args):
            p = (ROOT / line)
            if p.suffix in _REF_SUFFIXES and p.is_file():
                seen.add(p.resolve())
    return sorted(seen)


def _changed_files() -> set[Path]:
    out: set[Path] = set()
    for args in (
        ["git", "diff", "HEAD", "--name-only"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        for line in _git_lines(args):
            out.add((ROOT / line).resolve())
    return out


def _staged_files() -> set[Path]:
    out: set[Path] = set()
    for line in _git_lines(["git", "diff", "--cached", "--name-only"]):
        out.add((ROOT / line).resolve())
    return out


def _staged_blob(rel: str) -> str | None:
    res = subprocess.run(
        ["git", "show", f":{rel}"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        return None
    return res.stdout


def _existing_adr_ids() -> set[str]:
    """现存 ADR 号:decisions/NNNN-slug.md 或 decisions/NNNN-slug/(文件夹形)。"""
    ids: set[str] = set()
    if not DECISIONS.is_dir():
        return ids
    for entry in DECISIONS.iterdir():
        stem = entry.name[:-3] if entry.name.endswith(".md") else entry.name
        if _is_adr_stem(stem) and (entry.is_file() and entry.name.endswith(".md") or entry.is_dir()):
            ids.add(_FILENAME_RE.match(stem).group(1))
    return ids


def _adr_main_files() -> list[Path]:
    """每个 ADR 的主 md:单文件 decisions/NNNN-slug.md,或文件夹 decisions/NNNN-slug/NNNN-slug.md。"""
    out: list[Path] = []
    if not DECISIONS.is_dir():
        return out
    for entry in sorted(DECISIONS.iterdir()):
        if entry.is_file() and entry.name.endswith(".md"):
            if _is_adr_stem(entry.name[:-3]):
                out.append(entry)
        elif entry.is_dir() and _is_adr_stem(entry.name):
            main = entry / f"{entry.name}.md"  # 主 md 与文件夹同名(不叫 README)
            if main.is_file():
                out.append(main)
    return out


def check_adr_frontmatter(path: Path, *, content: str | None = None) -> list[tuple[str, int, str]]:
    """校验单个 ADR:frontmatter.id 与文件名 NNNN 一致 + status 在枚举内。"""
    rel = str(path.relative_to(ROOT))
    stem = path.stem
    m = _FILENAME_RE.match(stem)
    fname_id = m.group(1) if m else None

    lines = (content if content is not None else path.read_text(encoding="utf-8")).splitlines()
    if not lines or lines[0].strip() != "---":
        return [(rel, 1, "ADR 缺 frontmatter(首行应为 ---)")]

    fm_id = fm_status = None
    for i, line in enumerate(lines[1:], start=2):
        if line.strip() == "---":
            break
        if (mm := _ID_RE.match(line)):
            fm_id = mm.group(1).zfill(4)
        elif (ms := _STATUS_RE.match(line)):
            fm_status = ms.group(1)

    v: list[tuple[str, int, str]] = []
    if fm_id is None:
        v.append((rel, 1, "frontmatter 缺 id"))
    elif fname_id and fm_id != fname_id:
        v.append((rel, 1, f"frontmatter.id({fm_id}) 与文件名({fname_id}) 不一致"))
    if fm_status is None:
        v.append((rel, 1, "frontmatter 缺 status"))
    elif fm_status not in VALID_STATUS:
        v.append((rel, 1, f"status 非法: {fm_status}(须 {'|'.join(sorted(VALID_STATUS))})"))
    return v


def find_dead_refs(changed_only: bool, staged_only: bool = False) -> list[tuple[str, str, list[str]]]:
    """`ADR-NNNN` 引用指向不存在的 ADR。"""
    ids = _existing_adr_ids()
    if staged_only:
        scope = _staged_files()
    elif changed_only:
        scope = _changed_files()
    else:
        scope = None
    refs: dict[str, list[str]] = {}
    for p in _repo_text_files():
        if p.stem.endswith("-template"):
            continue
        if scope is not None and p.resolve() not in scope:
            continue
        if staged_only and p.resolve() in scope:
            rel = str(p.relative_to(ROOT))
            blob = _staged_blob(rel)
            if blob is None:
                continue
            lines = blob.splitlines()
        else:
            lines = p.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines, 1):
            for m in _REF_RE.finditer(line):
                refs.setdefault(m.group(1), []).append(f"{p.relative_to(ROOT)}:{i}")
    return sorted((nnnn, "", locs) for nnnn, locs in refs.items() if nnnn not in ids)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--changed", action="store_true", help="只检查本轮 git 改动(验收用)")
    mode.add_argument("--staged", action="store_true", help="只检查 index 待提交 blob(pre-commit 用)")
    args = ap.parse_args()

    if args.staged:
        scope_label = "待提交(staged)"
        scope = _staged_files()
    elif args.changed:
        scope_label = "本轮改动"
        scope = _changed_files()
    else:
        scope_label = "全仓"
        scope = None
    had_issue = False

    # 1) ADR frontmatter/命名
    fm_violations: list[tuple[str, int, str]] = []
    for main_md in _adr_main_files():
        if scope is not None and main_md.resolve() not in scope:
            continue
        if args.staged:
            rel = str(main_md.relative_to(ROOT))
            blob = _staged_blob(rel)
            if blob is None:
                continue
            fm_violations.extend(check_adr_frontmatter(main_md, content=blob))
        else:
            fm_violations.extend(check_adr_frontmatter(main_md))
    if fm_violations:
        had_issue = True
        print(f"ADR 结构检查({scope_label}):{len(fm_violations)} 处违规 ✗")
        for path, line, msg in fm_violations:
            print(f"  {path}:{line}  {msg}")
    else:
        print(f"ADR 结构检查({scope_label}):无违规 ✓")

    # 2) ADR-NNNN 断链
    dead = find_dead_refs(args.changed, staged_only=args.staged)
    if dead:
        had_issue = True
        print(f"ADR-NNNN 断链检查({scope_label}):{len(dead)} 处断链 ✗")
        for nnnn, _, locs in dead:
            print(f"  ADR-{nnnn}  <-  {'; '.join(locs)}")
    else:
        print(f"ADR-NNNN 断链检查({scope_label}):无断链 ✓")

    if had_issue:
        return 1
    print("无问题 ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
