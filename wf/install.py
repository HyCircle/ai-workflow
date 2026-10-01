"""wf init:把 kit 投影进目标仓的 .workflow/,建后端技能入口,写本地忽略规则。重跑即升级。"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from wf import KIT, SEED

BEGIN = "# —— ai-workflow BEGIN(.workflow 投影 + 后端入口,本地忽略;wf init 生成,勿手改)——"
END = "# —— ai-workflow END ——"
ENTRY_DIRS = {"cc": ".claude", "codex": ".agents"}


def _skills_entry(root: Path, dirname: str) -> None:
    """建 <dirname>/skills → ../.workflow/kit/skills 相对软链;已有别的内容时不动并提示。"""
    entry, target = root / dirname / "skills", "../.workflow/kit/skills"
    if entry.is_symlink() and os.readlink(entry) == target:
        return
    if entry.exists() or entry.is_symlink():
        print(f"⚠ {entry} 已存在且不是本工作流的入口,未改动;需要时手动改为指向 {target} 的软链")
        return
    entry.parent.mkdir(exist_ok=True)
    entry.symlink_to(target)
    print(f"✓ {dirname}/skills → {target}")


def _exclude(root: Path, track: bool, dirs: list[str]) -> None:
    path = root / ".git/info/exclude"
    path.parent.mkdir(exist_ok=True)
    kept, inside = [], False
    for line in path.read_text(encoding="utf-8").splitlines() if path.exists() else []:
        if "ai-workflow BEGIN" in line:
            inside = True
        elif "ai-workflow END" in line:
            inside = False
        elif not inside:
            kept.append(line)
    ours = ["/.workflow/kit/", "/.workflow/workflow.env", "/.workflow/scratchpad/"] if track else ["/.workflow/", "/AGENTS.md"]
    path.write_text("\n".join([*kept, BEGIN, *ours, *(f"/{d}/" for d in dirs), END]) + "\n", encoding="utf-8")


def init(root: Path, track: bool, backends: list[str]) -> int:
    wf = root / ".workflow"
    wf.mkdir(exist_ok=True)
    shutil.rmtree(wf / "kit", ignore_errors=True)
    shutil.copytree(KIT, wf / "kit")
    print(f"✓ 机制副本 → {wf / 'kit'}")

    for src, dst in [(KIT / "workflow.env.example", wf / "workflow.env"),
                     (SEED / "decisions/0000-template.md", wf / "decisions/0000-template.md"),
                     (SEED / "AGENTS.md", root / "AGENTS.md")]:
        if not dst.exists():
            dst.parent.mkdir(exist_ok=True)
            shutil.copyfile(src, dst)
            print(f"✓ 新建 {dst.relative_to(root)}")

    # cursor 能读 .claude 与 .agents,只在它是唯一后端时借 .claude 入口
    dirs = [ENTRY_DIRS[b] for b in backends if b in ENTRY_DIRS] or [".claude"]
    for d in dirs:
        _skills_entry(root, d)
    if "cursor" in backends:
        dirs.append(".cursor")
    _exclude(root, track, dirs)
    print(f"✓ 忽略规则写入 .git/info/exclude({'track' if track else 'no-track'})")
    print("下一步:在 .workflow/workflow.env 填测试命令与模型档;在 AGENTS.md「项目工具约定」填技术栈。")
    return 0
