"""外呼原语:把提示词交给某个后端 CLI,最终回复写到 out,原始输出流实时写进日志(可 tail -f)。

后端写法「后端/模型」,省前缀 = cursor。退出码:0 正常;124 超时;3 后端报错或找不到;4 没拿到最终回复。
"""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import tempfile
from pathlib import Path

TIMEOUT_RC = 124
BACKENDS = ("cursor", "codex", "claude")


def split_spec(spec: str) -> tuple[str, str]:
    backend, _, model = spec.partition("/")
    return (backend, model) if model else ("cursor", spec)


def _argv(backend: str, model: str, prompt: str, write: bool, last_msg: Path) -> tuple[list[str], bool]:
    """返回 (命令行, 提示词是否走标准输入)。只读靠 CLI 自带模式或提示词约束,不启用沙箱。"""
    if backend == "cursor":
        mode = ["--force"] if write else ["--mode", "ask"]
        return ["cursor-agent", "-p", prompt, "--model", model, "--output-format", "stream-json", "--trust", *mode], False
    if backend == "claude":
        argv = ["claude", "-p", "--model", model, "--output-format", "stream-json", "--verbose",
                "--dangerously-skip-permissions"]
        if not write:
            argv += ["--disallowedTools", "Edit,Write,NotebookEdit"]
        return argv, True
    return ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox", "-m", model,
            "--json", "-o", str(last_msg), "-"], True


def _events(log: Path) -> list[dict]:
    out = []
    for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            out.append(obj)
    return out


def _parse(backend: str, log: Path, last_msg: Path) -> tuple[int, str, str]:
    """从日志与 codex 的末条消息文件提取 (rc, 回复, 用量)。"""
    events = _events(log)
    if backend == "codex":
        usage = next((json.dumps(e["usage"]) for e in reversed(events) if e.get("type") == "turn.completed"), "")
        text = last_msg.read_text(encoding="utf-8").strip() if last_msg.is_file() else ""
        if text:
            return 0, text, usage
        err = next((e for e in reversed(events) if e.get("type") in ("turn.failed", "error")), None)
        return (3, f"<<<AGENT-ERROR: {json.dumps(err, ensure_ascii=False)}>>>", usage) if err else (4, "", usage)
    # cursor 与 claude 的流都以 type=result 事件收尾
    result = next((e for e in reversed(events) if e.get("type") == "result"), None)
    if result is None:
        return 4, "", ""
    usage = json.dumps(result.get("usage") or {})
    if result.get("subtype") == "success" and not result.get("is_error") and result.get("result"):
        return 0, result["result"], usage
    return 3, f"<<<AGENT-ERROR: {result.get('result') or result.get('error') or result.get('subtype')}>>>", usage


def call(spec: str, prompt: str, *, log: Path, cwd: Path, timeout: int = 0, write: bool = False) -> tuple[int, str, str]:
    """跑一次外呼,返回 (rc, 回复, 用量)。rc=4 时回复为日志尾部,便于定位。"""
    backend, model = split_spec(spec)
    if backend not in BACKENDS:
        return 3, f"<<<AGENT-ERROR: 未知后端 {backend}(支持 {'|'.join(BACKENDS)})>>>", ""
    log.parent.mkdir(parents=True, exist_ok=True)
    last_msg = log.with_suffix(".last.txt")
    argv, via_stdin = _argv(backend, model, prompt, write, last_msg)
    if not shutil.which(argv[0]):
        return 3, f"<<<AGENT-ERROR: 找不到 {argv[0]}>>>", ""

    with tempfile.TemporaryFile() as stdin, open(log, "wb") as out:
        if via_stdin:
            stdin.write(prompt.encode("utf-8"))
            stdin.seek(0)
        proc = subprocess.Popen(argv, cwd=cwd, stdin=stdin if via_stdin else subprocess.DEVNULL,
                                stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            proc.wait(timeout=timeout or None)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            return TIMEOUT_RC, f"<<<AGENT-TIMEOUT: {timeout} 秒>>>", ""

    rc, text, usage = _parse(backend, log, last_msg)
    last_msg.unlink(missing_ok=True)
    if rc == 4:
        tail = log.read_text(encoding="utf-8", errors="replace")[-3000:]
        text = f"<<<AGENT-NO-RESULT: 进程退出码 {proc.returncode},未拿到最终回复。日志尾部:>>>\n{tail}"
    return rc, text, usage
