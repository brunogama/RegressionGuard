#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Validate a generated agent repository without network or LLM access."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# Matches unresolved Jinja markers (double-brace, block, comment) but not
# GitHub's dollar-brace expressions.
JINJA_BLOCK_MARKER = re.compile(r"\x7b[%#]")
JINJA_VARIABLE_MARKER = re.compile(r"(?<!\$)\x7b\x7b(?P<expression>[^\n{}]+)\x7d\x7d")
PYTHON_F_STRING_PREFIX = re.compile(r"(?:^|[^A-Za-z0-9_])(?:fr|rf|f)[\"'][^\n]*$")
SKILL_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
TEXT_SUFFIXES = {".json", ".md", ".py", ".toml", ".txt", ".yml", ".yaml"}

# Files every checkout must carry, whatever harness is in use.
#
# `qa/QA_AGENT.md` and `qa/RUBRIC.md` were carried over from the template this script came from
# and have never existed in this repository, so the check failed on every run and told nobody
# anything. RegressionGuard routes QA through `CONTEXT.md` for language and `.scratch/tickets/`
# for the contract a change is judged against, both of which are required below instead.
REQUIRED_PATHS = (
    "AGENTS.md",
    "CONTEXT.md",
    "scripts/qa_repository.py",
)

# A harness is enabled by the presence of its directory, and each enabled
# harness owes the files that give an agent its instructions and its QA route.
HARNESS_REQUIREMENTS = {
    ".claude": ("CLAUDE.md", ".claude/agents/qa.md", ".claude/commands/qa.md"),
    ".pi": (".pi/settings.json", ".pi/prompts/qa.md"),
    ".agents": (".agents/agents/qa.md", ".agents/commands/qa.md"),
    ".codex": (".codex/prompts/qa.md",),
}

# Skill, command, prompt, and template files carry placeholders on purpose: a
# double-brace ARGUMENTS placeholder is command substitution, and a skill
# template is filled in when an agent uses it. The marker check is for prose and
# configuration that should already be final, so it does not read these.
TEMPLATED_PATH_MARKERS = ("/skills/", "/commands/", "/prompts/", "templates/")

# Captured transcripts of past agent runs. Their text is evidence of what a run
# did, including the absolute paths it printed, so scanning them for
# author-machine paths would report the recording rather than a defect.
ARCHIVED_RUN_PREFIXES = (".atomic/workflows/runs/", ".agents/evidence/")


class RepositoryQaError(RuntimeError):
    """Reports one or more generated repository validation failures."""


def _has_unresolved_jinja_marker(path: Path, text: str) -> bool:
    if JINJA_BLOCK_MARKER.search(text):
        return True
    for marker in JINJA_VARIABLE_MARKER.finditer(text):
        expression = marker.group("expression")
        if marker.start() > 0 and text[marker.start() - 1] == "=" and ":" in expression:
            continue
        line_start = text.rfind("\n", 0, marker.start()) + 1
        prefix = text[line_start:marker.start()]
        if path.suffix == ".py" and PYTHON_F_STRING_PREFIX.search(prefix):
            continue
        return True
    return False

def validate_repository(repository_root: Path) -> list[str]:
    """Return all deterministic QA failures for this repository."""
    failures: list[str] = []
    failures.extend(_validate_required_paths(repository_root))
    failures.extend(_validate_skill_frontmatter(repository_root))
    failures.extend(_validate_text_files(repository_root))
    failures.extend(_validate_external_sources(repository_root))
    failures.extend(_validate_workflow(repository_root))
    return failures


def _validate_required_paths(repository_root: Path) -> list[str]:
    required = list(REQUIRED_PATHS)
    for harness_directory, paths in HARNESS_REQUIREMENTS.items():
        if (repository_root / harness_directory).is_dir():
            required.extend(paths)
    return [f"required: missing {name}" for name in required if not (repository_root / name).is_file()]


def _validate_skill_frontmatter(repository_root: Path) -> list[str]:
    failures: list[str] = []
    skill_roots = [repository_root / ".claude/skills", repository_root / ".pi/skills", repository_root / ".agents/skills"]
    for skill_path in sorted(path for root in skill_roots if root.is_dir() for path in root.glob("*/SKILL.md")):
        text = skill_path.read_text(encoding="utf-8")
        if not text.startswith("---\n"):
            failures.append(f"skill: missing frontmatter {skill_path.relative_to(repository_root)}")
            continue
        frontmatter = text.split("---\n", 2)[1]
        name_match = re.search(r"^name:\s*([^\n]+)$", frontmatter, re.MULTILINE)
        description_match = re.search(r"^description:\s*([^\n]+)$", frontmatter, re.MULTILINE)
        if not name_match or not SKILL_NAME.fullmatch(name_match.group(1).strip()):
            failures.append(f"skill: invalid name {skill_path.relative_to(repository_root)}")
        if not description_match or not description_match.group(1).strip():
            failures.append(f"skill: missing description {skill_path.relative_to(repository_root)}")
    return failures


def _tracked_files(repository_root: Path) -> list[Path] | str:
    """Return the repository's tracked files, or a failure describing why it cannot."""
    try:
        listing = subprocess.run(
            ["git", "-C", str(repository_root), "ls-files", "-z"],
            capture_output=True,
            check=True,
            text=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        return f"tracked files: {error}"
    return [repository_root / name for name in listing.split("\0") if name]


def _validate_text_files(repository_root: Path) -> list[str]:
    """Check the repository's own text, which is what `git ls-files` reports.

    Walking the working tree instead would descend into `.git`, SwiftPM build
    output, and vendored checkouts, and report their contents as defects of this
    repository.
    """
    tracked = _tracked_files(repository_root)
    if isinstance(tracked, str):
        return [tracked]
    failures: list[str] = []
    for path in sorted(item for item in tracked if item.suffix in TEXT_SUFFIXES and item.is_file()):
        relative_name = path.relative_to(repository_root).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if not any(marker in f"/{relative_name}" for marker in TEMPLATED_PATH_MARKERS):
            if _has_unresolved_jinja_marker(path, text):
                failures.append(f"template: unresolved marker in {relative_name}")
        if relative_name.startswith(ARCHIVED_RUN_PREFIXES):
            continue
        if str(Path.home()) in text:
            failures.append(f"path: author-machine home path in {relative_name}")
    return failures


def _validate_external_sources(repository_root: Path) -> list[str]:
    failures: list[str] = []
    source_path = repository_root / "skill-sources.json"
    # Declaring no external skill sources is the safest state, not a defect; the
    # installer scan below still runs, because a script could add one directly.
    manifest: dict[str, Any] = {}
    if source_path.is_file():
        try:
            manifest = json.loads(source_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            return [f"external sources: {error}"]
    for source in manifest.get("sources", []):
        argv = source.get("install_argv", [])
        if argv[:3] != ["npx", "skills", "add"]:
            failures.append(f"external sources: invalid argv for {source.get('name', '<unnamed>')}")
        if source.get("enabled") and source.get("repository") == "owner/repository":
            failures.append("external sources: placeholder repository cannot be enabled")
    for script_path in (repository_root / "scripts").glob("*.py"):
        if script_path.name == "qa_repository.py":
            continue
        script = script_path.read_text(encoding="utf-8")
        if "subprocess" in script and "skills" in script and "add" in script:
            failures.append(f"external sources: automatic installer in {script_path.name}")
    return failures


def _validate_workflow(repository_root: Path) -> list[str]:
    workflow_path = repository_root / ".github/workflows/qa.yml"
    if not workflow_path.exists():
        return []
    workflow = workflow_path.read_text(encoding="utf-8")
    failures: list[str] = []
    if "qa_repository.py" not in workflow:
        failures.append("workflow: deterministic QA command missing")
    if "secrets." in workflow or "api_key" in workflow.lower():
        failures.append("workflow: QA must not require secrets")
    if "_candidates" in workflow and ("mv " in workflow or "move" in workflow):
        failures.append("workflow: candidate promotion automation is forbidden")
    return failures


def main(argv: list[str] | None = None) -> int:
    """Run repository QA and print a concise agent-friendly result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", nargs="?", type=Path, default=Path.cwd())
    arguments = parser.parse_args(argv or sys.argv[1:])
    failures = validate_repository(arguments.repository.resolve())
    if failures:
        print("Agent repository QA: FAIL", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Agent repository QA: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
