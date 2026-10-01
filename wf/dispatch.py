"""派单与审查:worker 在当前工作树施工,之后可选跑测试与独立审查,结果汇总回给负责人。

每次运行的产物放 .workflow/scratchpad/runs/<时间戳>/:brief.md 快照、提示词、报告、审查单、日志、summary.md。
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from wf import KIT
from wf.agent import call

# 负责人著作的文件;worker 改动它们属越界
PROTECTED = (".workflow/decisions", ".workflow/architecture.md", ".workflow/patterns", "AGENTS.md")
TIMEOUT_WORKER, TIMEOUT_REVIEW, TIMEOUT_TEST = 1800, 1200, 600


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=True).stdout


def _protected_state(root: Path) -> dict[str, str]:
    """受保护路径中有未提交改动的文件 → 内容哈希。前后对比得出 worker 动过的文件。"""
    paths = _git(root, "diff", "--name-only", "--no-renames", "-z", "HEAD", "--", *PROTECTED)
    paths += _git(root, "ls-files", "--others", "--exclude-standard", "-z", "--", *PROTECTED)
    state = {}
    for path in filter(None, paths.split("\0")):
        f = root / path
        state[path] = hashlib.sha256(f.read_bytes()).hexdigest() if f.is_file() else "deleted"
    return state


def _prompt(preamble: str, brief: str, test_cmd: str) -> str:
    text = (KIT / "skills/planner" / preamble).read_text(encoding="utf-8").replace("__TEST_CMD__", test_cmd or "(未配置)")
    return f"{(KIT / 'discipline.md').read_text(encoding='utf-8')}\n\n{text}{brief}"


class Run:
    def __init__(self, root: Path, brief_path: Path, cfg: dict[str, str]):
        self.root, self.cfg = root, cfg
        runs = root / ".workflow/scratchpad/runs"
        runs.mkdir(parents=True, exist_ok=True)
        self.dir = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=runs))
        shutil.copyfile(brief_path, self.dir / "brief.md")
        self.brief = (self.dir / "brief.md").read_text(encoding="utf-8")
        self.lines = [f"run 目录: {self.dir}", f"派单前: {_git(root, 'rev-parse', '--short', 'HEAD').strip()} "
                      f"({_git(root, 'branch', '--show-current').strip()})"]
        self.sections: list[tuple[str, str]] = []
        self.failed = False

    def _agent(self, name: str, spec: str, preamble: str, *, write: bool, timeout: int) -> str:
        prompt = _prompt(preamble, self.brief, self.cfg.get("WF_TEST_CMD", ""))
        (self.dir / f"{name}-prompt.md").write_text(prompt, encoding="utf-8")
        rc, text, usage = call(spec, prompt, log=self.dir / f"{name}.log", cwd=self.root, timeout=timeout, write=write)
        (self.dir / f"{name}.md").write_text(text + "\n", encoding="utf-8")
        self.lines.append(f"{name}: {spec} · 退出码 {rc} · 用量 {usage or '未知'}")
        self.failed |= rc != 0
        return text

    def work(self, spec: str) -> None:
        before = _protected_state(self.root)
        text = self._agent("report", spec, "worker-preamble.md", write=True, timeout=TIMEOUT_WORKER)
        after = _protected_state(self.root)
        touched = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
        self.lines.append(f"越界改动(负责人著作的文件): {', '.join(touched) if touched else '无'}")
        self.sections.append(("worker 报告(自述,待核实)", text))

    def test(self) -> None:
        cmd = self.cfg.get("WF_TEST_CMD")
        if not cmd:
            self.lines.append("测试: 未配置 WF_TEST_CMD,未运行")
            return
        try:
            p = subprocess.run(cmd, shell=True, cwd=self.root, capture_output=True, text=True, timeout=TIMEOUT_TEST)
            rc, out = p.returncode, p.stdout + p.stderr
        except subprocess.TimeoutExpired as e:
            rc, out = 124, f"{e.stdout or ''}{e.stderr or ''}\n<<<超时 {TIMEOUT_TEST} 秒>>>"
        (self.dir / "test.log").write_text(out, encoding="utf-8")
        self.lines.append(f"测试: `{cmd}` → {'通过' if rc == 0 else f'失败(退出码 {rc})'},全文见 test.log")
        if rc != 0:
            self.sections.append(("测试输出尾部", "\n".join(out.splitlines()[-30:])))

    def review(self, spec: str) -> None:
        text = self._agent("review", spec, "review-preamble.md", write=False, timeout=TIMEOUT_REVIEW)
        self.sections.append((f"独立审查({spec})", text))

    def finish(self) -> int:
        status = _git(self.root, "status", "--short") or "(工作树干净)\n"
        parts = ["═══════ 回给负责人 ═══════", *self.lines, ""]
        for title, body in [*self.sections, ("git status", status.rstrip())]:
            parts += [f"──── {title} ────", body.rstrip(), ""]
        summary = "\n".join(parts)
        (self.dir / "summary.md").write_text(summary, encoding="utf-8")
        print(summary)
        (self.dir / ".done").touch()
        return 2 if self.failed else 0
