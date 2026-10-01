"""wf 的端到端测试:真实 wf 代码路径,只把三个模型 CLI 换成受控假程序(tests/fake_cli.py)。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

from wf.agent import call
from wf.cli import main

FAKE = Path(__file__).parent / "fake_cli.py"


@pytest.fixture
def fake(tmp_path, monkeypatch):
    """把 cursor-agent / claude / codex 指向假程序;返回读取其调用记录的函数。"""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in ("cursor-agent", "claude", "codex"):
        (bin_dir / name).symlink_to(FAKE)
    record = tmp_path / "record.json"
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("FAKE_RECORD", str(record))
    return lambda: json.loads(record.read_text())


@pytest.fixture
def repo(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    root.mkdir()
    for cmd in (["init", "-q"], ["config", "user.email", "t@t"], ["config", "user.name", "t"]):
        subprocess.run(["git", *cmd], cwd=root, check=True)
    (root / "app.py").write_text("x = 1\n")
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=root, check=True)
    monkeypatch.chdir(root)
    return root


@pytest.mark.parametrize("backend", ["cursor", "claude", "codex"])
def test_call_returns_final_reply(fake, tmp_path, monkeypatch, backend):
    monkeypatch.setenv("FAKE_TEXT", "最终报告")
    rc, text, usage = call(f"{backend}/m1", "提示词全文", log=tmp_path / "a.log", cwd=tmp_path)
    assert (rc, text) == (0, "最终报告")
    assert usage
    rec = fake()
    prompt_seen = rec["stdin"] if backend != "cursor" else rec["argv"][rec["argv"].index("-p") + 1]
    assert prompt_seen == "提示词全文"


def test_read_only_and_write_flags(fake, tmp_path):
    call("claude/m", "p", log=tmp_path / "a.log", cwd=tmp_path)
    assert "--disallowedTools" in fake()["argv"]
    call("claude/m", "p", log=tmp_path / "a.log", cwd=tmp_path, write=True)
    assert "--disallowedTools" not in fake()["argv"]
    call("cursor/m", "p", log=tmp_path / "a.log", cwd=tmp_path)
    assert "ask" in fake()["argv"] and "--force" not in fake()["argv"]


@pytest.mark.parametrize("backend", ["cursor", "codex"])
def test_agent_error_and_missing_result(fake, tmp_path, monkeypatch, backend):
    monkeypatch.setenv("FAKE_MODE", "error")
    rc, text, _ = call(f"{backend}/m", "p", log=tmp_path / "a.log", cwd=tmp_path)
    assert rc == 3 and "AGENT-ERROR" in text
    monkeypatch.setenv("FAKE_MODE", "none")
    rc, text, _ = call(f"{backend}/m", "p", log=tmp_path / "a.log", cwd=tmp_path)
    assert rc == 4 and "AGENT-NO-RESULT" in text and "half-line" in text


def test_timeout_kills_process_tree(fake, tmp_path, monkeypatch):
    monkeypatch.setenv("FAKE_MODE", "sleep")
    pidfile = tmp_path / "child.pid"
    monkeypatch.setenv("FAKE_CHILD_PIDFILE", str(pidfile))
    start = time.time()
    rc, _, _ = call("cursor/m", "p", log=tmp_path / "a.log", cwd=tmp_path, timeout=1)
    assert rc == 124 and time.time() - start < 10
    child = int(pidfile.read_text())
    time.sleep(0.2)
    with pytest.raises(ProcessLookupError):
        os.kill(child, 0)


def test_unknown_backend_and_missing_cli(tmp_path, monkeypatch):
    assert call("gemini/m", "p", log=tmp_path / "a.log", cwd=tmp_path)[0] == 3
    monkeypatch.setenv("PATH", str(tmp_path))
    rc, text, _ = call("codex/m", "p", log=tmp_path / "a.log", cwd=tmp_path)
    assert rc == 3 and "找不到 codex" in text


def _setup_workflow(repo: Path, test_cmd: str) -> Path:
    wf = repo / ".workflow"
    (wf / "decisions").mkdir(parents=True)
    (wf / "workflow.env").write_text(
        f'WF_TEST_CMD="{test_cmd}"\nWF_WORKER_MODEL="cursor/w"   # 注释\nWF_REVIEW_MODEL="claude/r"\n')
    brief = wf / "brief.md"
    brief.write_text("目标：改 app.py\n")
    return brief


def test_run_with_review_reports_overreach_and_tests(fake, repo, monkeypatch, capsys):
    brief = _setup_workflow(repo, "exit 3")
    # 派单前就存在的 ADR 改动不算 worker 越界
    (repo / ".workflow/decisions/0001-a.md").write_text("负责人刚写的\n")
    (repo / ".workflow/decisions/ab c.md").write_text("也是派单前就有的\n")
    monkeypatch.setenv("FAKE_TEXT", "报告正文")
    monkeypatch.setenv("FAKE_TOUCH", "app.py,AGENTS.md,.workflow/decisions/ab c.md")
    rc = main(["run", str(brief), "--review"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "越界改动(负责人著作的文件): .workflow/decisions/ab c.md, AGENTS.md\n" in out
    assert "失败(退出码 3)" in out
    assert "report: cursor/w · 退出码 0" in out and "review: claude/r · 退出码 0" in out
    run_dir = next((repo / ".workflow/scratchpad/runs").iterdir())
    for name in ("brief.md", "report.md", "review.md", "test.log", "summary.md", ".done", "report.log"):
        assert (run_dir / name).exists(), name
    prompt = (run_dir / "review-prompt.md").read_text()
    assert "少即是多" in prompt and prompt.endswith("目标：改 app.py\n")
    assert "exit 3" in (run_dir / "report-prompt.md").read_text()


def test_run_failure_exit_code_and_review_only(fake, repo, monkeypatch, capsys):
    brief = _setup_workflow(repo, "true")
    monkeypatch.setenv("FAKE_MODE", "error")
    assert main(["run", str(brief)]) == 2
    monkeypatch.delenv("FAKE_MODE")
    assert main(["review", str(brief), "--model", "codex/x"]) == 0
    out = capsys.readouterr().out
    assert "review: codex/x" in out and "测试: `true` → 通过" in out and "report:" not in out.split("═══")[-1]


def test_ask_role_alias_and_out(fake, repo, monkeypatch):
    _setup_workflow(repo, "true")
    (repo / "p.md").write_text("问题")
    monkeypatch.setenv("FAKE_TEXT", "回答")
    assert main(["ask", "review", "p.md", "--out", "o/r.md"]) == 0
    assert (repo / "o/r.md").read_text() == "回答\n"
    assert fake()["argv"][0].endswith("claude")


def test_init_projects_kit_entries_and_exclude(repo, capsys):
    (repo / ".agents/skills").mkdir(parents=True)  # 项目自有内容不被覆盖
    assert main(["init", str(repo), "--backends", "cc,codex,cursor"]) == 0
    assert main(["init", str(repo), "--backends", "cc,codex,cursor"]) == 0
    assert (repo / ".workflow/kit/skills/planner/SKILL.md").is_file()
    assert (repo / ".workflow/workflow.env").is_file() and (repo / "AGENTS.md").is_file()
    assert os.readlink(repo / ".claude/skills") == "../.workflow/kit/skills"
    assert (repo / ".claude/skills/holistic/SKILL.md").is_file()
    assert not (repo / ".agents/skills").is_symlink()
    assert "未改动" in capsys.readouterr().out
    exclude = (repo / ".git/info/exclude").read_text()
    assert exclude.count("ai-workflow BEGIN") == 1
    assert "/.workflow/kit/" in exclude and "/.cursor/" in exclude
    assert main(["init", str(repo), "--no-track"]) == 0
    exclude = (repo / ".git/info/exclude").read_text()
    assert "/.workflow/\n" in exclude and "/.workflow/kit/" not in exclude
    status = subprocess.run(["git", "status", "--porcelain"], cwd=repo, capture_output=True, text=True).stdout
    assert status == ""


def test_module_entry_point():
    out = subprocess.run([sys.executable, "-m", "wf", "--help"], capture_output=True, text=True,
                         cwd=Path(__file__).parent.parent)
    assert out.returncode == 0 and "review" in out.stdout
