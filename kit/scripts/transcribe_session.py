#!/usr/bin/env python3
"""Deterministic Claude Code session JSONL → markdown transcript.

Keeps all natural language; tool_use → one-line skeletons; drops tool_result
bodies and empty thinking. Consecutive tool-only assistant turns merge into
one section. No LLM, no network, stdlib only. Best-effort secret redaction
before write.
"""

from __future__ import annotations

import argparse
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
_SKELETON_VALUE_KEYS = frozenset({"file_path", "path", "command", "pattern"})

_SECRET_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"sk-[A-Za-z0-9_-]{8,}"), "***MASKED***"),
    (re.compile(r"AKIA[A-Z0-9]{16}"), "***MASKED***"),
    (re.compile(r"Bearer\s+\S+", re.IGNORECASE), "Bearer ***MASKED***"),
    (
        re.compile(r"(?i)(api[_-]?key|token|password|secret)\s*[=:]\s*\S+"),
        r"\1=***MASKED***",
    ),
]


def munge_project_dir(path: str) -> str:
    """Map cwd to Claude projects directory name."""
    abspath = os.path.abspath(path)
    return re.sub(r"[^A-Za-z0-9]", "-", abspath)


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
            if key == "command":
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
    kind: str  # text | thinking | tool
    text: str = ""
    tool_name: str = ""
    tool_input: Any = field(default_factory=dict)


@dataclass
class ParsedSection:
    role: str  # user | assistant
    parts: list[ParsedPart] = field(default_factory=list)

    @property
    def has_nl(self) -> bool:
        return any(p.kind in ("text", "thinking") and p.text for p in self.parts)

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
    if block_type == "text":
        return ParsedPart(kind="text", text=str(block.get("text", "")))
    if block_type == "thinking":
        thinking = str(block.get("thinking", ""))
        if not thinking:
            return None
        return ParsedPart(kind="thinking", text=thinking)
    if block_type == "tool_use":
        return ParsedPart(
            kind="tool",
            tool_name=str(block.get("name", "?")),
            tool_input=block.get("input", {}),
        )
    if block_type == "tool_result":
        return None
    return None


def parse_record(record: dict[str, Any]) -> ParsedSection | None:
    """Parse one user/assistant JSONL record into a structured section."""
    rec_type = record.get("type")
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
        parts.append(ParsedPart(kind="text", text=content))
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            parsed = parse_block(block)
            if parsed is not None:
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


def parse_sections(records: list[dict[str, Any]]) -> list[ParsedSection]:
    """Parse dialogue records into structured sections."""
    sections: list[ParsedSection] = []
    for rec in records:
        parsed = parse_record(rec)
        if parsed is not None:
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
    if part.kind == "thinking":
        lines = ["> [thinking]", *[f"> {line}" for line in part.text.splitlines()]]
        return "\n".join(lines)
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


def transcribe(records: list[dict[str, Any]]) -> TranscriptResult:
    """Render filtered dialogue records to markdown transcript."""
    sections = merge_tool_only_assistant_runs(parse_sections(records))
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
    cwd: str | None = None,
) -> Path:
    """Resolve --jsonl or --session to a filesystem path."""
    if jsonl and session:
        raise ValueError("Use either --jsonl or --session, not both")
    if jsonl:
        return Path(jsonl)
    if session:
        base = Path.home() / ".claude" / "projects" / munge_project_dir(cwd or os.getcwd())
        return base / f"{session}.jsonl"
    raise ValueError("Either --jsonl or --session is required")


def load_records(path: Path) -> tuple[list[dict[str, Any]], int]:
    text = path.read_text(encoding="utf-8")
    return parse_jsonl_lines(text.splitlines())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Transcribe Claude Code session JSONL to markdown."
    )
    parser.add_argument("--jsonl", help="Path to session .jsonl file")
    parser.add_argument("--session", help="Session ID (resolves under ~/.claude/projects/)")
    parser.add_argument("--out", required=True, help="Output markdown path")
    args = parser.parse_args(argv)

    try:
        jsonl_path = resolve_jsonl_path(args.jsonl, args.session)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not jsonl_path.is_file():
        print(f"error: JSONL not found: {jsonl_path}", file=sys.stderr)
        return 1

    records, skipped = load_records(jsonl_path)
    result = transcribe(records)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(result.text, encoding="utf-8")

    print(
        f"transcribed dialogue_records={result.dialogue_records} "
        f"skipped_malformed={skipped} "
        f"chars={result.chars}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
