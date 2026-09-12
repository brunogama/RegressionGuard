#!/usr/bin/env python3
"""Run a configured formatter and stage the files it successfully fixes."""

from __future__ import annotations

import subprocess
import sys


FORMATTERS: dict[str, tuple[list[str], set[int]]] = {
    "swift-format": (
        ["swift-format", "-i", "--configuration", ".swift-format"],
        {0},
    ),
    "trailing-whitespace": (["trailing-whitespace-fixer"], {0, 1}),
    "end-of-file": (["end-of-file-fixer"], {0, 1}),
    "mixed-line-ending": (["mixed-line-ending", "--fix=lf"], {0, 1}),
}


def main(arguments: list[str]) -> int:
    if len(arguments) < 2 or arguments[1] not in FORMATTERS:
        choices = ", ".join(sorted(FORMATTERS))
        print(f"usage: {arguments[0]} <{choices}> [file ...]", file=sys.stderr)
        return 2

    formatter, successful_statuses = FORMATTERS[arguments[1]]
    files = arguments[2:]
    result = subprocess.run([*formatter, *files], check=False)
    if result.returncode not in successful_statuses:
        return result.returncode
    if not files:
        return 0

    return subprocess.run(["git", "add", "--", *files], check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
