#!/usr/bin/env python3
"""Archive a dialogue or model-written compact with source provenance; no deletion."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

from transcribe_session import mask_secrets


def verify_archive(source: Path, archived: Path) -> None:
    text = archived.read_text(encoding="utf-8")
    first, body = text.split("\n\n", 1)
    line = first.splitlines()[0]
    if not line.startswith("<!-- workflow-archive ") or not line.endswith(" -->"):
        raise ValueError("archive has no verifiable metadata; review legacy archive manually")
    metadata = json.loads(line[len("<!-- workflow-archive "):-len(" -->")])
    if metadata.get("transcript_sha256") != hashlib.sha256(source.read_bytes()).hexdigest():
        raise ValueError("source transcript changed since archive was written")
    if metadata.get("body_sha256") != hashlib.sha256(body.encode()).hexdigest():
        raise ValueError("archive body is incomplete or changed")


def archive(source: Path, compact: Path, directory: Path, slug: str) -> Path:
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug):
        raise ValueError("slug must contain lowercase words separated by hyphens")
    original = source.read_text(encoding="utf-8")
    if not re.search(r"(?m)^## (User|Assistant)\s*$", original):
        raise ValueError("source must be an extracted dialogue")
    content = compact.read_text(encoding="utf-8")
    if not re.search(r"(?m)^## (User|Assistant)\s*$", content):
        raise ValueError("archive must contain dialogue headings, not just a report")
    match = re.search(r"^<!-- workflow-transcript (.+) -->$", original, re.M)
    provenance = json.loads(match.group(1)) if match else {"session": source.parent.name, "backend": "legacy"}
    metadata = {
        "transcript": str(source.resolve()),
        "transcript_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "provenance": provenance,
    }
    directory.mkdir(parents=True, exist_ok=True)
    body = mask_secrets(content).strip() + "\n"
    metadata["body_sha256"] = hashlib.sha256(body.encode()).hexdigest()
    maximum = 0
    for path in directory.glob("*.transcript.compact.md"):
        prefix = re.match(r"(\d+)-", path.name)
        if prefix:
            maximum = max(maximum, int(prefix.group(1)))
        first = path.read_text(encoding="utf-8").splitlines()[0:1]
        if not first or not first[0].startswith("<!-- workflow-archive "):
            continue
        existing = json.loads(first[0][len("<!-- workflow-archive "):-len(" -->")])
        if existing.get("transcript_sha256") == metadata["transcript_sha256"] and existing.get("transcript") == metadata["transcript"]:
            if existing.get("body_sha256") == metadata["body_sha256"]:
                verify_archive(source, path)
                return path
            raise ValueError(f"source already archived with different content: {path}; review it explicitly")
    day = datetime.now(timezone.utc).strftime("%Y%m%d")
    header = "<!-- workflow-archive " + json.dumps(metadata, ensure_ascii=False) + " -->\n"
    header += (f"> session {provenance['session']} | "
               f"原 {len(original)} 字符 → {len(body)} 字符 | 对话记忆，事实以仓内证据为准\n\n")
    path = directory / f"{maximum + 1:02d}-{day}-{slug}.transcript.compact.md"
    with path.open("x", encoding="utf-8") as stream:
        stream.write(header + body)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="finishing transcript.md")
    parser.add_argument("--compact", type=Path, help="model-written compact dialogue; required for archiving")
    parser.add_argument("--archive-dir", type=Path, default=Path(".workflow/scratchpad/_archive"))
    parser.add_argument("--slug")
    parser.add_argument("--verify", type=Path, help="Verify existing archive integrity and matching source; no writes")
    args = parser.parse_args()
    try:
        if args.verify:
            verify_archive(args.source, args.verify)
            print(f"verified: {args.verify}")
            return 0
        if not args.slug or not args.compact:
            raise ValueError("--compact and --slug are required when creating an archive")
        print(archive(args.source, args.compact, args.archive_dir, args.slug))
    except (OSError, ValueError, KeyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
