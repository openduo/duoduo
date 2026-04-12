#!/usr/bin/env python3
"""Patch Markdown frontmatter while preserving comments and body text."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


KEY_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*:")


def read_sections(path: Path) -> tuple[list[str], list[str]]:
    raw = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = raw.splitlines()
    if lines and lines[0] == "---":
        try:
            end = lines.index("---", 1)
        except ValueError as exc:
            raise SystemExit(f"Unterminated frontmatter in {path}") from exc
        return lines[1:end], lines[end + 1 :]
    return [], lines


def render_value(raw: str) -> str:
    try:
      value = json.loads(raw)
    except json.JSONDecodeError:
      value = raw

    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    return json.dumps(value, ensure_ascii=False)


def write_sections(path: Path, frontmatter: list[str], body: list[str]) -> None:
    output: list[str] = ["---", *frontmatter, "---"]
    if body:
        output.extend(["", *body])
    else:
        output.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(output) + "\n", encoding="utf-8")


def set_key(frontmatter: list[str], key: str, raw_value: str) -> list[str]:
    rendered = f"{key}: {render_value(raw_value)}"
    new_lines: list[str] = []
    replaced = False
    for line in frontmatter:
        match = KEY_RE.match(line.strip())
        if match and match.group(1) == key and not line.lstrip().startswith("#"):
            if not replaced:
                new_lines.append(rendered)
                replaced = True
            continue
        new_lines.append(line)
    if not replaced:
        new_lines.append(rendered)
    return new_lines


def unset_key(frontmatter: list[str], key: str) -> list[str]:
    new_lines: list[str] = []
    for line in frontmatter:
        match = KEY_RE.match(line.strip())
        if match and match.group(1) == key and not line.lstrip().startswith("#"):
            continue
        new_lines.append(line)
    return new_lines


def replace_body(body_file: Path) -> list[str]:
    return body_file.read_text(encoding="utf-8").rstrip("\n").splitlines()


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("file")
    set_parser.add_argument("key")
    set_parser.add_argument("value")

    unset_parser = subparsers.add_parser("unset")
    unset_parser.add_argument("file")
    unset_parser.add_argument("key")

    body_parser = subparsers.add_parser("replace-body")
    body_parser.add_argument("file")
    body_parser.add_argument("--text-file", required=True)

    args = parser.parse_args()
    target = Path(args.file).expanduser()
    frontmatter, body = read_sections(target)

    if args.command == "set":
        frontmatter = set_key(frontmatter, args.key, args.value)
    elif args.command == "unset":
        frontmatter = unset_key(frontmatter, args.key)
    else:
        body = replace_body(Path(args.text_file).expanduser())

    write_sections(target, frontmatter, body)


if __name__ == "__main__":
    main()
