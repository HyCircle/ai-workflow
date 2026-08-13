#!/usr/bin/env python3
"""Deterministic Claude Code session JSONL → markdown transcript.

Mechanical conversion for Cursor /cleaning: keep natural language, compress
tool noise to skeletons, budget by approx tokens (soft cap). No LLM, no
network, stdlib only.

Compression ladder (only tool noise; never silently hard-truncate NL):
  0 skeleton       — tool_use skeleton, no tool_result body, drop empty thinking
  1 tight_args     — shorter tool args (path-only / shorter command)
  2 tools_elide_old — elide oldest pure-tool sections
  3 warn           — prepend TRUNCATED_BUDGET; still no NL hard-cut
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
TOOL_COMMAND_SKELETON = 80
TOOL_COMMAND_TIGHT = 40
DEFAULT_MAX_TOTAL_TOKENS = 100_000

LEVEL_SKELETON = 0
LEVEL_TIGHT_ARGS = 1
LEVEL_TOOLS_ELIDE_OLD = 2
LEVEL_WARN = 3

LEVEL_NAMES = {
    LEVEL_SKELETON: "skeleton",
    LEVEL_TIGHT_ARGS: "tight_args",
    LEVEL_TOOLS_ELIDE_OLD: "tools_elide_old",
    LEVEL_WARN: "warn",
}

TOOL_ELIDE_MARKER = "[… 省略工具 ×{n} …]"
TRUNCATED_BUDGET_HEADER = "TRUNCATED_BUDGET"

# Key fields kept with values in tool skeletons; others listed as key names only.
_SKELETON_VALUE_KEYS = frozenset({"file_path", "path", "command", "pattern"})

_SECRET_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"sk-[A-Za-z0-9_-]{8,}"), "***MASKED***"),
    (re.compile(r"AKIA[A-Z0-9]{16}"), "***MASKED***"),
    (re.compile(r"Bearer\s+\S+", re.IGNORECASE), "Bearer ***MASKED***"),
    (
        re.compile(
            r"(?i)(api[_-]?key|token|password|secret)\s*[=:]\s*\S+"
        ),
        r"\1=***MASKED***",
    ),
]


def approx_tokens(text: str) -> int:
    """Heuristic token estimate (fixed; no tiktoken).

    Each CJK Unified Ideograph in U+4E00..U+9FFF counts as 1 token.
    All other characters together count as ``len // 4`` (floor).
    Total = cjk_count + other_count // 4.
    """
    cjk = 0
    other = 0
    for ch in text:
        if "\u4e00" <= ch <= "\u9fff":
            cjk += 1
        else:
            other += 1
    return cjk + other // 4


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


def format_tool_args(inp: Any, *, tight: bool) -> str:
    """Render tool input as a single-line skeleton.

    Keeps values for file_path / path / command (truncated) / pattern;
    other keys appear as names only. Total length capped at TOOL_INPUT_MAX_CHARS.
    """
    if not isinstance(inp, dict):
        raw = json.dumps(inp, ensure_ascii=False, separators=(",", ":"))
        return _cap_str(raw, TOOL_INPUT_MAX_CHARS)

    cmd_limit = TOOL_COMMAND_TIGHT if tight else TOOL_COMMAND_SKELETON
    pieces: list[str] = []
    other_keys: list[str] = []

    for key, value in inp.items():
        if tight:
            if key in ("file_path", "path"):
                pieces.append(
                    f"{json.dumps(key, ensure_ascii=False)}:"
                    f"{json.dumps(str(value), ensure_ascii=False)}"
                )
            elif key == "command":
                pieces.append(
                    f"{json.dumps(key, ensure_ascii=False)}:"
                    f"{json.dumps(_cap_str(str(value), cmd_limit), ensure_ascii=False)}"
                )
            else:
                other_keys.append(str(key))
            continue

        if key in _SKELETON_VALUE_KEYS:
            rendered = str(value)
            if key == "command":
                rendered = _cap_str(rendered, cmd_limit)
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
    def tool_count(self) -> int:
        return sum(1 for p in self.parts if p.kind == "tool")


@dataclass
class TranscriptResult:
    text: str
    dialogue_records: int
    chars: int
    approx_tokens: int
    compression_level: int
    truncated: bool

    @property
    def compression_name(self) -> str:
        return LEVEL_NAMES.get(self.compression_level, str(self.compression_level))


def parse_block(block: dict[str, Any]) -> ParsedPart | None:
    """Parse one content block; None if unsupported or empty-skip."""
    block_type = block.get("type")
    if block_type == "text":
        return ParsedPart(kind="text", text=str(block.get("text", "")))
    if block_type == "thinking":
        thinking = str(block.get("thinking", ""))
        if not thinking:
            return None  # drop empty thinking
        return ParsedPart(kind="thinking", text=thinking)
    if block_type == "tool_use":
        return ParsedPart(
            kind="tool",
            tool_name=str(block.get("name", "?")),
            tool_input=block.get("input", {}),
        )
    if block_type == "tool_result":
        # Default: drop result body (cleaning re-reads the repo).
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


def filter_dialogue_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep only user/assistant records with message, excluding isMeta/sidechain."""
    kept: list[dict[str, Any]] = []
    for rec in records:
        if rec.get("type") not in ("user", "assistant"):
            continue
        if rec.get("isMeta") is True:
            continue
        if rec.get("isSidechain") is True:
            continue
        if not isinstance(rec.get("message"), dict):
            continue
        kept.append(rec)
    return kept


def _render_part(part: ParsedPart, *, tight: bool) -> str:
    if part.kind == "text":
        return part.text
    if part.kind == "thinking":
        lines = ["> [thinking]", *[f"> {line}" for line in part.text.splitlines()]]
        return "\n".join(lines)
    if part.kind == "tool":
        args = format_tool_args(part.tool_input, tight=tight)
        return f"[tool] {part.tool_name}({args})"
    return ""


def render_section(section: ParsedSection, *, tight: bool) -> str | None:
    """Render one parsed section; None if nothing left to show."""
    parts = [_render_part(p, tight=tight) for p in section.parts]
    parts = [p for p in parts if p]
    if not parts:
        return None
    heading = "## User" if section.role == "user" else "## Assistant"
    return f"{heading}\n\n" + "\n\n".join(parts)


@dataclass
class _Renderable:
    """Section text plus metadata for the elision ladder."""

    text: str
    has_nl: bool
    tool_count: int
    elided: bool = False


def _build_renderables(
    sections: list[ParsedSection],
    *,
    tight: bool,
) -> list[_Renderable]:
    out: list[_Renderable] = []
    for sec in sections:
        rendered = render_section(sec, tight=tight)
        if rendered is None:
            continue
        out.append(
            _Renderable(
                text=rendered,
                has_nl=sec.has_nl,
                tool_count=sec.tool_count,
            )
        )
    return out


def _join_renderables(items: list[_Renderable]) -> str:
    return "\n\n".join(r.text for r in items)


def _elide_old_tool_sections(
    items: list[_Renderable],
    max_total_tokens: int,
) -> list[_Renderable]:
    """From oldest, replace pure-tool sections with an elision marker until under budget."""
    result = [
        _Renderable(r.text, r.has_nl, r.tool_count, r.elided) for r in items
    ]
    for i, item in enumerate(result):
        if approx_tokens(_join_renderables(result)) <= max_total_tokens:
            break
        if item.has_nl or item.elided or item.tool_count <= 0:
            continue
        n = item.tool_count
        result[i] = _Renderable(
            text=TOOL_ELIDE_MARKER.format(n=n),
            has_nl=False,
            tool_count=n,
            elided=True,
        )
    return result


def _budget_warning(tokens: int, max_total_tokens: int, level: int) -> str:
    name = LEVEL_NAMES.get(level, str(level))
    return (
        f"> **{TRUNCATED_BUDGET_HEADER}**: approx_tokens={tokens} "
        f"> max_total_tokens={max_total_tokens}; compression_level={name} ({level}). "
        f"Natural language was not hard-truncated; reduce session scope or raise the soft cap."
    )


def mask_secrets(text: str) -> str:
    """Best-effort redaction of common secret patterns."""
    masked = text
    for pattern, repl in _SECRET_PATTERNS:
        masked = pattern.sub(repl, masked)
    return masked


def parse_sections(records: list[dict[str, Any]]) -> list[ParsedSection]:
    """Filter + parse dialogue records into structured sections."""
    sections: list[ParsedSection] = []
    for rec in filter_dialogue_records(records):
        parsed = parse_record(rec)
        if parsed is not None:
            sections.append(parsed)
    return sections


def transcribe(
    records: list[dict[str, Any]],
    max_total_tokens: int = DEFAULT_MAX_TOTAL_TOKENS,
) -> TranscriptResult:
    """Render filtered dialogue records to markdown transcript.

    Budget is a soft token cap. Over budget → compression ladder (tool noise only).
    Never silently hard-truncates natural-language text with ``text[:N]+"..."``.
    """
    sections = parse_sections(records)
    dialogue_count = len(filter_dialogue_records(records))

    # Level 0–1: render, check budget
    for level, tight in (
        (LEVEL_SKELETON, False),
        (LEVEL_TIGHT_ARGS, True),
    ):
        renderables = _build_renderables(sections, tight=tight)
        body = mask_secrets(_join_renderables(renderables))
        tokens = approx_tokens(body)
        if tokens <= max_total_tokens:
            return TranscriptResult(
                text=body,
                dialogue_records=dialogue_count,
                chars=len(body),
                approx_tokens=tokens,
                compression_level=level,
                truncated=False,
            )

    # Level 2: elide oldest pure-tool sections (tight args)
    renderables = _build_renderables(sections, tight=True)
    renderables = _elide_old_tool_sections(renderables, max_total_tokens)
    body = mask_secrets(_join_renderables(renderables))
    tokens = approx_tokens(body)
    if tokens <= max_total_tokens:
        return TranscriptResult(
            text=body,
            dialogue_records=dialogue_count,
            chars=len(body),
            approx_tokens=tokens,
            compression_level=LEVEL_TOOLS_ELIDE_OLD,
            truncated=True,
        )

    # Level 3: warn only — do not hard-truncate NL / handoff
    warning = _budget_warning(tokens, max_total_tokens, LEVEL_WARN)
    body = mask_secrets(warning + "\n\n" + _join_renderables(renderables))
    tokens = approx_tokens(body)
    return TranscriptResult(
        text=body,
        dialogue_records=dialogue_count,
        chars=len(body),
        approx_tokens=tokens,
        compression_level=LEVEL_WARN,
        truncated=True,
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
        description=(
            "Transcribe Claude Code session JSONL to markdown "
            "(tool skeleton + token soft cap)."
        )
    )
    parser.add_argument("--jsonl", help="Path to session .jsonl file")
    parser.add_argument("--session", help="Session ID (resolves under ~/.claude/projects/)")
    parser.add_argument("--out", required=True, help="Output markdown path")
    parser.add_argument(
        "--max-total-tokens",
        type=int,
        default=DEFAULT_MAX_TOTAL_TOKENS,
        help=f"Soft cap in approx tokens (default: {DEFAULT_MAX_TOTAL_TOKENS})",
    )
    args = parser.parse_args(argv)

    max_tokens = args.max_total_tokens

    try:
        jsonl_path = resolve_jsonl_path(args.jsonl, args.session)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not jsonl_path.is_file():
        print(f"error: JSONL not found: {jsonl_path}", file=sys.stderr)
        return 1

    records, skipped = load_records(jsonl_path)
    result = transcribe(records, max_total_tokens=max_tokens)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(result.text, encoding="utf-8")

    truncated_flag = "yes" if result.truncated else "no"
    print(
        f"transcribed dialogue_records={result.dialogue_records} "
        f"skipped_malformed={skipped} "
        f"chars={result.chars} "
        f"approx_tokens={result.approx_tokens} "
        f"compression_level={result.compression_name} "
        f"truncated={truncated_flag}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
