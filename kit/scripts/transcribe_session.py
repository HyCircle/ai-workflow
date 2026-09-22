#!/usr/bin/env python3
"""Local CC/Codex/Cursor logs → dialogue; stdlib only, no model calls.

Keep user/assistant text verbatim, excluding harness envelopes and reasoning.
Tool skeletons are opt-in. This is extraction, not semantic summarization.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

TOOL_INPUT_MAX_CHARS = 200
TOOL_COMMAND_CHARS = 80

# Values kept in tool skeletons; other keys listed as names only.
_SKELETON_VALUE_KEYS = frozenset({"file_path", "path", "command", "cmd", "pattern"})

_SECRET_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"sk-[A-Za-z0-9_-]{8,}"), "***MASKED***"),
    (re.compile(r"AKIA[A-Z0-9]{16}"), "***MASKED***"),
    (re.compile(r"Bearer\s+\S+", re.IGNORECASE), "Bearer ***MASKED***"),
    (
        re.compile(r'''(?i)((?:api[_-]?key|token|password|secret)["']?\s*[=:]\s*)(?:"[^"\n]+"|'[^'\n]+'|[^\s,;}]+)'''),
        r"\1***MASKED***",
    ),
]


def _cap_str(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    if max_chars <= 3:
        return text[:max_chars]
    return text[: max_chars - 3] + "..."


def format_tool_args(inp: Any) -> str:
    """Render tool input as a single-line skeleton."""
    if not isinstance(inp, dict):
        raw = json.dumps(inp, ensure_ascii=False, separators=(",", ":"))
        return _cap_str(raw, TOOL_INPUT_MAX_CHARS)

    pieces: list[str] = []
    other_keys: list[str] = []

    for key, value in inp.items():
        if key in _SKELETON_VALUE_KEYS:
            rendered = str(value)
            if key in ("command", "cmd"):
                rendered = _cap_str(rendered, TOOL_COMMAND_CHARS)
            pieces.append(
                f"{json.dumps(key, ensure_ascii=False)}:"
                f"{json.dumps(rendered, ensure_ascii=False)}"
            )
        else:
            other_keys.append(str(key))

    if other_keys:
        keys_lit = ",".join(json.dumps(k, ensure_ascii=False) for k in other_keys)
        pieces.append(f'"_keys":[{keys_lit}]')

    body = "{" + ",".join(pieces) + "}"
    return _cap_str(body, TOOL_INPUT_MAX_CHARS)


@dataclass
class ParsedPart:
    kind: str  # text | tool
    text: str = ""
    tool_name: str = ""
    tool_input: Any = field(default_factory=dict)


@dataclass
class ParsedSection:
    role: str  # user | assistant
    parts: list[ParsedPart] = field(default_factory=list)

    @property
    def has_nl(self) -> bool:
        return any(p.kind == "text" and p.text for p in self.parts)

    @property
    def tool_only(self) -> bool:
        return (
            self.role == "assistant"
            and not self.has_nl
            and any(p.kind == "tool" for p in self.parts)
        )


@dataclass
class TranscriptResult:
    text: str
    dialogue_records: int
    chars: int


def parse_block(block: dict[str, Any]) -> ParsedPart | None:
    """Parse one content block; None if unsupported or empty-skip."""
    block_type = block.get("type")
    if block_type in ("text", "input_text", "output_text"):
        return ParsedPart(kind="text", text=str(block.get("text", "")))
    if block_type in ("image", "input_image"):
        return ParsedPart(kind="text", text="[附件：图像；文本转写不含图像内容]")
    if block_type == "tool_use":
        return ParsedPart(
            kind="tool",
            tool_name=str(block.get("name", "?")),
            tool_input=block.get("input", {}),
        )
    if block_type == "tool_result":
        return None
    return None


def clean_text(text: str, role: str) -> str:
    """Remove known harness envelopes only; do not guess semantic importance."""
    if role == "user":
        if text.startswith("# AGENTS.md instructions for ") and "<INSTRUCTIONS>" in text:
            text = re.sub(r"^# AGENTS\.md instructions for .*?</INSTRUCTIONS>", "", text, flags=re.S)
        # Cursor wraps the user's actual words; keep everything inside verbatim.
        text = re.sub(r"</?user_query>", "", text)
        for tag in ("environment_context", "system-reminder", "timestamp", "ide_opened_file", "ide_selection"):
            text = re.sub(rf"<{tag}\b[^>]*>.*?</{tag}>", "", text, flags=re.S)
    return text.strip()


def parse_record(record: dict[str, Any]) -> ParsedSection | None:
    """Parse one user/assistant JSONL record into a structured section."""
    rec_type = record.get("type", record.get("role"))
    if rec_type == "response_item":
        message = record.get("payload", {})
        if message.get("type") == "message":
            if message.get("channel") in ("analysis", "summary"):
                return None
            return parse_record({"type": message.get("role"), "message": message})
        if message.get("type") in ("function_call", "custom_tool_call"):
            inp = message.get("arguments", message.get("input", ""))
            if isinstance(inp, str):
                try:
                    inp = json.loads(inp)
                except json.JSONDecodeError:
                    inp = {"input": inp}
            return ParsedSection("assistant", [ParsedPart("tool", tool_name=message.get("name", "?"), tool_input=inp)])
        return None
    if rec_type not in ("user", "assistant"):
        return None
    if record.get("isMeta") is True:
        return None
    if record.get("isSidechain") is True:
        return None
    message = record.get("message")
    if not isinstance(message, dict):
        return None

    content = message.get("content")
    parts: list[ParsedPart] = []

    if isinstance(content, str):
        parts.append(ParsedPart(kind="text", text=clean_text(content, rec_type)))
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            parsed = parse_block(block)
            if parsed is not None:
                if parsed.kind == "text":
                    parsed.text = clean_text(parsed.text, rec_type)
                parts.append(parsed)
    else:
        return None

    if not parts:
        return None
    return ParsedSection(role=rec_type, parts=parts)


def parse_jsonl_lines(
    lines: list[str],
) -> tuple[list[dict[str, Any]], int]:
    """Parse JSONL lines; return (records, skipped_malformed_count)."""
    records: list[dict[str, Any]] = []
    skipped = 0
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            skipped += 1
            continue
        if not isinstance(obj, dict):
            skipped += 1
            continue
        records.append(obj)
    return records, skipped


def parse_sections(records: list[dict[str, Any]], tools: bool = False) -> list[ParsedSection]:
    """Parse dialogue records into structured sections."""
    sections: list[ParsedSection] = []
    seen_ids: set[str] = set()
    for rec in records:
        # CC repeats records when resuming; dedup identity, never repeated user words.
        identity = rec.get("uuid")
        if identity and identity in seen_ids:
            continue
        if identity:
            seen_ids.add(identity)
        parsed = parse_record(rec)
        if parsed is not None:
            parsed.parts = [p for p in parsed.parts if (p.kind == "text" and p.text) or (tools and p.kind == "tool")]
            if parsed.parts:
                sections.append(parsed)
    return sections


def merge_tool_only_assistant_runs(
    sections: list[ParsedSection],
) -> list[ParsedSection]:
    """Fold consecutive tool-only assistant sections into one."""
    merged: list[ParsedSection] = []
    for sec in sections:
        if merged and sec.tool_only and merged[-1].tool_only:
            merged[-1].parts.extend(sec.parts)
            continue
        merged.append(sec)
    return merged


def _render_part(part: ParsedPart) -> str:
    if part.kind == "text":
        return part.text
    if part.kind == "tool":
        return f"[tool] {part.tool_name}({format_tool_args(part.tool_input)})"
    return ""


def render_section(section: ParsedSection) -> str | None:
    """Render one parsed section; None if nothing left to show."""
    parts = [p for p in (_render_part(p) for p in section.parts) if p]
    if not parts:
        return None
    heading = "## User" if section.role == "user" else "## Assistant"
    return f"{heading}\n\n" + "\n\n".join(parts)


def mask_secrets(text: str) -> str:
    """Best-effort redaction of common secret patterns."""
    masked = text
    for pattern, repl in _SECRET_PATTERNS:
        masked = pattern.sub(repl, masked)
    return masked


def transcribe(records: list[dict[str, Any]], tools: bool = False) -> TranscriptResult:
    """Render filtered dialogue records to markdown transcript."""
    sections = merge_tool_only_assistant_runs(parse_sections(records, tools))
    chunks: list[str] = []
    for sec in sections:
        rendered = render_section(sec)
        if rendered is not None:
            chunks.append(rendered)
    body = mask_secrets("\n\n".join(chunks))
    return TranscriptResult(
        text=body,
        dialogue_records=len(sections),
        chars=len(body),
    )


def resolve_jsonl_path(
    jsonl: str | None,
    session: str | None,
    backend: str = "auto",
) -> Path:
    """Resolve --jsonl or --session to a filesystem path."""
    if jsonl and session:
        raise ValueError("Use either --jsonl or --session, not both")
    if jsonl:
        return Path(jsonl)
    if session:
        if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", session):
            raise ValueError("--session requires a full UUID; use --input for an explicit file")
        candidates: list[Path] = []
        home = Path.home()
        if backend in ("auto", "cc"):
            candidates.extend((home / ".claude/projects").glob(f"*/{session}.jsonl"))
        if backend in ("auto", "codex"):
            base = Path(os.environ.get("CODEX_HOME", str(home / ".codex")))
            for directory in ("sessions", "archived_sessions"):
                candidates.extend((base / directory).rglob(f"rollout-*-{session}.jsonl"))
        if backend in ("auto", "cursor"):
            base = home / ".cursor/projects"
            for pattern in (f"*/agent-transcripts/{session}/{session}.jsonl", f"*/agent-transcripts/{session}.jsonl"):
                candidates.extend(base.glob(pattern))
        candidates = sorted(set(p.resolve() for p in candidates))
        if len(candidates) != 1:
            raise ValueError(f"Expected one source for {session}, found {len(candidates)}; pass --input explicitly: {candidates}")
        return candidates[0]
    raise ValueError("Either --jsonl or --session is required")


def load_records(path: Path) -> tuple[list[dict[str, Any]], int]:
    text = path.read_text(encoding="utf-8")
    return parse_jsonl_lines(text.splitlines())


def source_info(path: Path, records: list[dict[str, Any]], backend: str) -> dict[str, str]:
    if backend == "auto":
        backend = ("codex" if any(r.get("type") in ("session_meta", "response_item") for r in records)
                   else "cursor" if any(r.get("role") in ("user", "assistant") for r in records)
                   else "cc")
    ids = re.findall(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", path.stem)
    return {"backend": backend, "session": ids[-1] if ids else path.stem,
            "source": str(path.resolve()), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Extract CC/Codex/Cursor dialogue without a model call."
    )
    parser.add_argument("--input", "--jsonl", dest="jsonl", help="Explicit session .jsonl path")
    parser.add_argument("--session", help="Full session UUID; exact lookup across local backends")
    parser.add_argument("--backend", choices=("auto", "cc", "codex", "cursor"), default="auto")
    parser.add_argument("--tools", action="store_true", help="Include tool skeletons for investigation")
    parser.add_argument("--out", required=True, help="Output markdown path")
    args = parser.parse_args(argv)

    try:
        jsonl_path = resolve_jsonl_path(args.jsonl, args.session, backend=args.backend)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not jsonl_path.is_file():
        print(f"error: JSONL not found: {jsonl_path}", file=sys.stderr)
        return 1

    records, skipped = load_records(jsonl_path)
    if skipped:
        print(f"error: {skipped} malformed records; retry after log flush or repair the source", file=sys.stderr)
        return 1
    result = transcribe(records, args.tools)
    if not result.dialogue_records:
        print("error: no supported dialogue found; output was not written", file=sys.stderr)
        return 1
    metadata = source_info(jsonl_path, records, args.backend)
    metadata["mode"] = "dialogue+tools" if args.tools else "dialogue"
    header = "<!-- workflow-transcript " + json.dumps(metadata, ensure_ascii=False) + " -->\n"
    header += "> 本文件为机械提取的对话；保留用户/助手正文，省略推理、工具输出和系统注入。工具执行结果需回仓核实。\n\n"

    out_path = Path(args.out)
    if out_path.resolve() == jsonl_path.resolve():
        print("error: output must differ from source", file=sys.stderr)
        return 1
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(header + result.text + "\n", encoding="utf-8")

    print(
        f"transcribed dialogue_records={result.dialogue_records} "
        f"skipped_malformed={skipped} "
        f"chars={result.chars}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
