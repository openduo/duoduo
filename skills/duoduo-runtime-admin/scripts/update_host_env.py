#!/usr/bin/env python3
"""Upsert or remove keys in ~/.config/duoduo/.env while preserving comments."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


LINE_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")


def render_value(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./:@-]+", value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(encoding="utf-8").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def set_key(lines: list[str], key: str, value: str) -> list[str]:
    rendered = f"{key}={render_value(value)}"
    new_lines: list[str] = []
    replaced = False
    for line in lines:
        match = LINE_RE.match(line)
        if match and match.group(1) == key:
            if not replaced:
                new_lines.append(rendered)
                replaced = True
            continue
        new_lines.append(line)
    if not replaced:
        new_lines.append(rendered)
    return new_lines


def unset_key(lines: list[str], key: str) -> list[str]:
    return [
        line
        for line in lines
        if not (LINE_RE.match(line) and LINE_RE.match(line).group(1) == key)
    ]


def get_key(lines: list[str], key: str) -> str:
    for line in lines:
        match = LINE_RE.match(line)
        if match and match.group(1) == key:
            return match.group(2)
    raise SystemExit(f"{key} is not set")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="~/.config/duoduo/.env")
    subparsers = parser.add_subparsers(dest="command", required=True)

    set_parser = subparsers.add_parser("set")
    set_parser.add_argument("key")
    set_parser.add_argument("value")

    unset_parser = subparsers.add_parser("unset")
    unset_parser.add_argument("key")

    get_parser = subparsers.add_parser("get")
    get_parser.add_argument("key")

    args = parser.parse_args()
    target = Path(args.file).expanduser()
    lines = read_lines(target)

    if args.command == "set":
        write_lines(target, set_key(lines, args.key, args.value))
    elif args.command == "unset":
        write_lines(target, unset_key(lines, args.key))
    else:
        print(get_key(lines, args.key))


if __name__ == "__main__":
    main()
