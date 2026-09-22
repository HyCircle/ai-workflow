"""Behavioral fixtures for the three observed log formats and archive boundary."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import transcribe_session as extract
from archive_transcript import archive, verify_archive

SESSION = "b8e6e706-f4dd-4fd0-9e79-964be0aa5300"


def cc(role, content, **extra):
    return {"type": role, "message": {"content": content}, **extra}


def codex(role, text, **extra):
    return {"type": "response_item", "payload": {"type": "message", "role": role,
            "content": [{"type": "input_text" if role == "user" else "output_text", "text": text}], **extra}}


class TranscriptTests(unittest.TestCase):
    def test_cc_preserves_corrections_and_removes_tools_reasoning(self):
        records = [cc("user", "先不要提交；上次的判断错了。", uuid="u"),
                   cc("assistant", [{"type": "thinking", "thinking": "reasoning noise"},
                                    {"type": "tool_use", "name": "Bash", "input": {"command": "pytest"}},
                                    {"type": "text", "text": "尚未验证。"}]),
                   cc("user", [{"type": "tool_result", "content": "large output"}]),
                   cc("user", "injected skill", isMeta=True),
                   cc("assistant", "child", isSidechain=True)]
        records.append(records[0])
        body = extract.transcribe(records).text
        self.assertEqual(body, "## User\n\n先不要提交；上次的判断错了。\n\n## Assistant\n\n尚未验证。")
        self.assertIn("[tool] Bash", extract.transcribe(records, tools=True).text)

    def test_codex_uses_one_channel_and_keeps_handoff(self):
        records = [codex("developer", "system noise"),
                   codex("user", "# AGENTS.md instructions for /repo\n<INSTRUCTIONS>injected</INSTRUCTIONS>\n<environment_context>env</environment_context>"),
                   codex("user", "目标：先审查"), codex("assistant", "reasoning", channel="analysis"),
                   {"type": "event_msg", "payload": {"type": "user_message", "message": "目标：先审查"}},
                   {"type": "compacted", "payload": {"replacement_history": [codex("user", "目标：先审查")["payload"]]}},
                   codex("assistant", "下 session 开场提示词：继续核验", channel="final")]
        body = extract.transcribe(records).text
        self.assertEqual(body.count("目标：先审查"), 1)
        self.assertNotIn("injected", body)
        self.assertNotIn("reasoning", body)
        self.assertIn("下 session 开场提示词", body)

    def test_cursor_jsonl_keeps_user_query(self):
        records = [{"role": "user", "message": {"content": [{"type": "text", "text": "<timestamp>date</timestamp><user_query>不要改 API\n原文保留</user_query>"}]}},
                   {"role": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"path": "x"}}, {"type": "text", "text": "同意"}]}}]
        self.assertEqual(extract.transcribe(records).text, "## User\n\n不要改 API\n原文保留\n\n## Assistant\n\n同意")

    def test_repeated_real_user_words_are_not_deduplicated(self):
        self.assertEqual(extract.transcribe([cc("user", "继续"), cc("user", "继续")]).text.count("继续"), 2)

    def test_redaction_and_image_placeholder(self):
        result = extract.transcribe([cc("user", [{"type": "text", "text": 'api_key="very sensitive value" Bearer abcdef'}, {"type": "image", "source": {"data": "binary"}}])]).text
        self.assertNotIn("sensitive", result)
        self.assertNotIn("abcdef", result)
        self.assertIn("图像", result)

    def test_exact_resolution_and_ambiguity(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(Path, "home", return_value=Path(tmp)), patch.dict(os.environ, {"CODEX_HOME": str(Path(tmp) / ".codex")}):
            for backend, relative in [("cc", f".claude/projects/other/{SESSION}.jsonl"),
                                      ("codex", f".codex/sessions/2026/09/22/rollout-date-{SESSION}.jsonl"),
                                      ("cursor", f".cursor/projects/other/agent-transcripts/{SESSION}/{SESSION}.jsonl")]:
                path = Path(tmp) / relative
                path.parent.mkdir(parents=True)
                path.touch()
                self.assertEqual(extract.resolve_jsonl_path(None, SESSION, backend=backend), path)
            with self.assertRaises(ValueError):
                extract.resolve_jsonl_path(None, SESSION)
            with self.assertRaises(ValueError):
                extract.resolve_jsonl_path(None, SESSION[:8])

    def test_cli_fails_without_clobbering_good_output(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stderr(io.StringIO()):
            source, output = Path(tmp) / "source.jsonl", Path(tmp) / "transcript.md"
            output.write_text("existing good transcript")
            for bad in ('{"unfinished":', '{"type":"unsupported"}\n'):
                source.write_text(bad)
                self.assertEqual(extract.main(["--input", str(source), "--out", str(output)]), 1)
                self.assertEqual(output.read_text(), "existing good transcript")

    def test_extract_archive_end_to_end(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            root = Path(tmp)
            source = root / f"{SESSION}.jsonl"
            source.write_text(json.dumps(cc("user", "不能提交")) + "\n" + json.dumps(cc("assistant", "交棒：测试未跑")))
            transcript = root / f"PL-{SESSION}" / "transcript.md"
            self.assertEqual(extract.main(["--input", str(source), "--out", str(transcript)]), 0)
            directory = root / "_archive"
            compact = root / "compact.md"
            compact.write_text("## User\n\n不能提交\n\n## Assistant\n\n交棒：测试未跑\n")
            result = archive(transcript, compact, directory, "test-session")
            self.assertIn(SESSION, result.read_text())
            self.assertEqual(archive(transcript, compact, directory, "test-session"), result)
            self.assertTrue(transcript.exists())
            verify_archive(transcript, result)
            result.write_text(result.read_text().replace("测试未跑", "测试全绿"))
            with self.assertRaises(ValueError):
                archive(transcript, compact, directory, "test-session")
            with self.assertRaises(ValueError):
                verify_archive(transcript, result)

    def test_archive_semantic_and_legacy_numbering(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, compact = root / "transcript.md", root / "compact.md"
            source.write_text("## User\n\n原始任务\n\n## Assistant\n\n尚未完成\n")
            compact.write_text("## User\n\n原始任务\n\n## Assistant\n\n未完成\n")
            directory = root / "_archive"
            directory.mkdir()
            (directory / "19-20260921-old.transcript.compact.md").write_text("legacy")
            result = archive(source, compact, directory, "test-semantic")
            self.assertTrue(result.name.startswith("20-"))
            self.assertIn("未完成", result.read_text())
            compact.write_text("not a dialogue")
            with self.assertRaises(ValueError):
                archive(source, compact, directory, "bad")

    def test_source_changed_blocks_archival_gc(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            root = Path(tmp)
            source, transcript = root / "source.jsonl", root / "transcript.md"
            source.write_text(json.dumps(cc("user", "用户约束")) + "\n")
            self.assertEqual(extract.main(["--input", str(source), "--out", str(transcript)]), 0)
            compact = root / "compact.md"
            compact.write_text("## User\n\n用户约束\n")
            result = archive(transcript, compact, root / "_archive", "source-check")
            transcript.write_text(transcript.read_text() + "\n## User\n\n新增约束\n")
            with self.assertRaises(ValueError):
                verify_archive(transcript, result)


if __name__ == "__main__":
    unittest.main()
