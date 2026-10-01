"""wf 命令入口:init / ask / run / review。"""

from __future__ import annotations

import argparse
import subprocess
import sys
from importlib.metadata import version
from pathlib import Path

ROLES = {"worker": "WF_WORKER_MODEL", "review": "WF_REVIEW_MODEL", "strong": "WF_REVIEW_MODEL_STRONG"}


def _root(start: Path) -> Path:
    p = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=start, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"✗ {start} 不在 git 仓库内")
    return Path(p.stdout.strip())


def _config(root: Path) -> dict[str, str]:
    """读 .workflow/workflow.env 的 KEY=值 行。"""
    cfg = {}
    path = root / ".workflow/workflow.env"
    for line in path.read_text(encoding="utf-8").splitlines() if path.exists() else []:
        key, sep, value = line.partition("=")
        if sep and not key.lstrip().startswith("#"):
            value = value.split(" #")[0].strip().strip("\"'")
            cfg[key.strip()] = value
    return cfg


def _model(spec: str, cfg: dict[str, str]) -> str:
    """worker / review / strong 取 workflow.env 中对应档位,其余原样当「后端/模型」。"""
    if spec in ROLES:
        if not cfg.get(ROLES[spec]):
            sys.exit(f"✗ workflow.env 未配置 {ROLES[spec]}")
        return cfg[ROLES[spec]]
    return spec


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wf", description="ai-workflow 命令行工具")
    ap.add_argument("--version", action="version", version=f"wf {version('ai-workflow')}")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init", help="安装或升级到目标 git 仓")
    p.add_argument("path", nargs="?", default=".")
    p.add_argument("--no-track", action="store_true", help="整个 .workflow/ 与 AGENTS.md 都不进 git")
    p.add_argument("--backends", default="cc", help="逗号分隔:cc,codex,cursor(默认 cc)")

    p = sub.add_parser("ask", help="外呼一个模型,默认只读")
    p.add_argument("model", help="worker|review|strong,或「后端/模型」")
    p.add_argument("prompts", nargs="+", type=Path, help="提示词文件,按顺序拼接")
    p.add_argument("--out", type=Path, help="回复写入此文件(默认打印)")
    p.add_argument("--log", type=Path, help="原始输出流日志(默认 --out 旁的 .log)")
    p.add_argument("--timeout", type=int, default=1200, help="秒,0 为不限(默认 1200)")
    p.add_argument("--write", action="store_true", help="允许改文件")

    p = sub.add_parser("run", help="派 worker 施工,可选跑测试与独立审查")
    p.add_argument("brief", type=Path)
    p.add_argument("--model", default="worker")
    p.add_argument("--review", nargs="?", const="review", metavar="MODEL", help="施工后跑测试与独立审查")

    p = sub.add_parser("review", help="对当前工作树跑测试与独立审查")
    p.add_argument("brief", type=Path)
    p.add_argument("--model", default="review")

    a = ap.parse_args(argv)
    if a.cmd == "init":
        from wf.install import init
        backends = [b for b in a.backends.split(",") if b]
        if bad := set(backends) - {"cc", "codex", "cursor"}:
            sys.exit(f"✗ 未知后端: {', '.join(bad)}")
        return init(_root(Path(a.path)), not a.no_track, backends)

    root = _root(Path.cwd())
    cfg = _config(root)
    if a.cmd == "ask":
        from wf.agent import call
        prompt = "\n\n".join(f.read_text(encoding="utf-8") for f in a.prompts)
        log = a.log or (a.out.with_suffix(".log") if a.out else root / ".workflow/scratchpad/ask.log")
        rc, text, usage = call(_model(a.model, cfg), prompt, log=log, cwd=root, timeout=a.timeout, write=a.write)
        if a.out:
            a.out.parent.mkdir(parents=True, exist_ok=True)
            a.out.write_text(text + "\n", encoding="utf-8")
        else:
            print(text)
        print(f"退出码 {rc} · 用量 {usage or '未知'} · 日志 {log}", file=sys.stderr)
        return rc

    from wf.dispatch import Run
    if not a.brief.is_file():
        sys.exit(f"✗ brief 不存在: {a.brief}")
    run = Run(root, a.brief, cfg)
    if a.cmd == "run":
        run.work(_model(a.model, cfg))
    if a.cmd == "review" or a.review:
        run.test()
        run.review(_model(a.model if a.cmd == "review" else a.review, cfg))
    return run.finish()
