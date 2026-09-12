#!/usr/bin/env python3
"""Emit filters for Swift tests impacted by files changed in Git.

Examples:
  impacted_swift_tests.py --base origin/main --target HEAD --format swift
  impacted_swift_tests.py --range v1.2.0..HEAD --format xcodebuild
  impacted_swift_tests.py --staged --dry-run
  impacted_swift_tests.py --working-tree --mapping-config test-map.json

The default mode uses a recognized CI pull-request base, then main or master,
and finally the working tree when the repository has no usable base ref.

The optional mapping file is JSON with these fields:
  {
    "ignore_paths": ["Vendor/**"],
    "source_mappings": {
      "Sources/Shared/**": ["AppTests/SharedTests"]
    },
    "target_mappings": {
      "Core": ["CoreTests", "IntegrationTests"]
    },
    "test_target_paths": {
      "Checks/**/*.swift": "IntegrationTests"
    }
  }

Canonical identifiers are Target, Target/Suite, or Target/Suite/testFunction.
This script deliberately emits suite-level selections for source changes because
every function in the suite may depend on the changed production code.
"""

from __future__ import annotations
import contextlib
import io

import argparse
import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


# Python's standard library was selected over a Bash/awk pipeline because Git's
# NUL-delimited rename records, JSON validation, portable globbing, and regex
# escaping are easier to keep correct on both macOS and Linux in one process.


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    diff_mode = parser.add_mutually_exclusive_group()
    diff_mode.add_argument("--base", metavar="REF", help="merge-base comparison ref")
    diff_mode.add_argument(
        "--range", dest="commit_range", metavar="RANGE", help="exact Git diff range"
    )
    diff_mode.add_argument(
        "--staged", action="store_true", help="inspect index changes"
    )
    diff_mode.add_argument(
        "--working-tree",
        action="store_true",
        help="inspect staged, unstaged, and untracked changes",
    )
    parser.add_argument("--target", metavar="REF", help="target ref used with --base")
    parser.add_argument(
        "--format",
        choices=("swift", "xcodebuild", "list"),
        default="list",
        help="output syntax (default: list)",
    )
    parser.add_argument(
        "--mapping-config", type=Path, metavar="PATH", help="custom JSON mapping file"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="emit canonical identifiers regardless of --format",
    )
    arguments = parser.parse_args(argv)
    if arguments.target and not arguments.base:
        parser.error("--target requires --base")
    return arguments


def run_git(repository: Path, *arguments: str) -> bytes:
    process = subprocess.run(
        ["git", *arguments], cwd=repository, check=False, capture_output=True
    )
    if process.returncode != 0:
        raise RuntimeError(process.stderr.decode("utf-8", errors="replace").strip())
    return process.stdout


def decode_paths(output: bytes) -> list[str]:
    return [
        path.decode("utf-8", errors="surrogateescape")
        for path in output.split(b"\0")
        if path
    ]


def decode_name_status(output: bytes) -> list[str]:
    fields = decode_paths(output)
    paths: list[str] = []
    index = 0
    while index < len(fields):
        status = fields[index]
        index += 1
        path_count = 2 if status.startswith(("R", "C")) else 1
        if index + path_count > len(fields):
            raise RuntimeError("git produced incomplete --name-status output")
        paths.extend(fields[index : index + path_count])
        index += path_count
    return paths


def ref_exists(repository: Path, ref: str) -> bool:
    process = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^" + "{commit}"],
        cwd=repository,
        check=False,
        capture_output=True,
    )
    return process.returncode == 0


def inferred_base(repository: Path) -> str | None:
    environment_names = (
        "GITHUB_BASE_REF",
        "BITRISEIO_GIT_BRANCH_DEST",
        "CI_MERGE_REQUEST_TARGET_BRANCH_NAME",
        "CI_PULL_REQUEST_TARGET_BRANCH",
    )
    for name in environment_names:
        branch = os.environ.get(name)
        if not branch:
            continue
        for candidate in (f"origin/{branch}", branch):
            if ref_exists(repository, candidate):
                return candidate
    for candidate in ("origin/main", "main", "origin/master", "master"):
        if ref_exists(repository, candidate) and candidate != "HEAD":
            return candidate
    return None


def collect_changed_paths(repository: Path, arguments: argparse.Namespace) -> list[str]:
    # Name-status with NUL separators preserves whitespace and gives both sides
    # of a rename. Keeping the old path lets Foo.swift still find FooTests.swift
    # when production code is renamed before its tests are reorganized.
    common = (
        "diff",
        "--name-status",
        "-z",
        "--find-renames",
        "--diff-filter=ACDMRTUXB",
    )
    if arguments.staged:
        return decode_name_status(run_git(repository, *common, "--cached"))
    if arguments.commit_range:
        return decode_name_status(run_git(repository, *common, arguments.commit_range))
    if arguments.base:
        target = arguments.target or "HEAD"
        return decode_name_status(
            run_git(repository, *common, f"{arguments.base}...{target}")
        )
    if arguments.working_tree:
        if ref_exists(repository, "HEAD"):
            tracked = decode_name_status(run_git(repository, *common, "HEAD"))
        else:
            tracked = decode_name_status(run_git(repository, *common, "--cached"))
            tracked.extend(decode_name_status(run_git(repository, *common)))
        untracked = decode_paths(
            run_git(repository, "ls-files", "--others", "--exclude-standard", "-z")
        )
        return sorted(set(tracked + untracked))
    base = inferred_base(repository)
    if base:
        return decode_name_status(run_git(repository, *common, f"{base}...HEAD"))
    if ref_exists(repository, "HEAD"):
        tracked = decode_name_status(run_git(repository, *common, "HEAD"))
    else:
        tracked = decode_name_status(run_git(repository, *common, "--cached"))
        tracked.extend(decode_name_status(run_git(repository, *common)))
    untracked = decode_paths(
        run_git(repository, "ls-files", "--others", "--exclude-standard", "-z")
    )
    return sorted(set(tracked + untracked))


@dataclass(frozen=True)
class TestFile:
    path: str
    target: str
    suites: frozenset[str]
    has_top_level_tests: bool
    contents: str

    @property
    def identifiers(self) -> set[str]:
        if self.has_top_level_tests:
            return {self.target}
        if self.suites:
            return {f"{self.target}/{suite}" for suite in self.suites}
        return {self.target}

    @property
    def imported_modules(self) -> set[str]:
        return set(
            re.findall(
                r"(?m)^\s*(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)",
                self.contents,
            )
        )


@dataclass(frozen=True)
class MappingConfig:
    ignore_paths: tuple[str, ...] = ()
    source_mappings: tuple[tuple[str, tuple[str, ...]], ...] = ()
    target_mappings: tuple[tuple[str, tuple[str, ...]], ...] = ()
    test_target_paths: tuple[tuple[str, str], ...] = ()


def require_string_list(value: object, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        raise RuntimeError(f"mapping config field '{field}' must be a list of strings")
    return tuple(value)


def load_mapping_config(repository: Path, path: Path | None) -> MappingConfig:
    """Load explicit mappings that take precedence over repository heuristics."""
    if path is None:
        return MappingConfig()
    config_path = path if path.is_absolute() else repository / path
    try:
        document = json.loads(config_path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(f"cannot read mapping config '{path}': {error}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"invalid JSON in mapping config '{path}': {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeError("mapping config must contain a JSON object")

    ignore_paths = require_string_list(document.get("ignore_paths", []), "ignore_paths")
    source_document = document.get("source_mappings", {})
    target_document = document.get("target_mappings", {})
    test_path_document = document.get("test_target_paths", {})
    if not isinstance(source_document, dict):
        raise RuntimeError("mapping config field 'source_mappings' must be an object")
    if not isinstance(target_document, dict):
        raise RuntimeError("mapping config field 'target_mappings' must be an object")
    if not isinstance(test_path_document, dict) or not all(
        isinstance(pattern, str) and pattern and isinstance(target, str) and target
        for pattern, target in test_path_document.items()
    ):
        raise RuntimeError(
            "mapping config field 'test_target_paths' must map globs to target names"
        )

    source_mappings: list[tuple[str, tuple[str, ...]]] = []
    for pattern, identifiers in source_document.items():
        if not isinstance(pattern, str) or not pattern:
            raise RuntimeError("source mapping globs must be nonempty strings")
        source_mappings.append(
            (pattern, require_string_list(identifiers, f"source_mappings.{pattern}"))
        )
    target_mappings: list[tuple[str, tuple[str, ...]]] = []
    for source_target, test_targets in target_document.items():
        if not isinstance(source_target, str) or not source_target:
            raise RuntimeError("target mapping keys must be nonempty strings")
        target_mappings.append(
            (
                source_target,
                require_string_list(test_targets, f"target_mappings.{source_target}"),
            )
        )
    return MappingConfig(
        ignore_paths,
        tuple(source_mappings),
        tuple(target_mappings),
        tuple((pattern, target) for pattern, target in test_path_document.items()),
    )


def strip_comments_and_strings(source: str) -> str:
    """Replace comments and string contents while preserving brace positions."""
    result = list(source)
    index = 0
    state = "code"
    while index < len(source):
        pair = source[index : index + 2]
        if state == "code" and pair == "//":
            state = "line_comment"
            result[index : index + 2] = "  "
            index += 2
            continue
        if state == "code" and pair == "/*":
            state = "block_comment"
            result[index : index + 2] = "  "
            index += 2
            continue
        if state == "line_comment":
            if source[index] == "\n":
                state = "code"
            else:
                result[index] = " "
            index += 1
            continue
        if state == "block_comment":
            if pair == "*/":
                result[index : index + 2] = "  "
                state = "code"
                index += 2
            else:
                if source[index] != "\n":
                    result[index] = " "
                index += 1
            continue
        if state == "code" and source[index] == '"':
            state = "string"
            result[index] = " "
            index += 1
            continue
        if state == "string":
            if source[index] == "\\":
                result[index] = " "
                if index + 1 < len(source):
                    result[index + 1] = " "
                index += 2
                continue
            if source[index] == '"':
                state = "code"
            if source[index] != "\n":
                result[index] = " "
            index += 1
            continue
        index += 1
    return "".join(result)


def matching_brace(source: str, opening: int) -> int | None:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def parse_test_suites(source: str) -> set[str]:
    sanitized = strip_comments_and_strings(source)
    xctest_suites = set(
        re.findall(
            r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)[^\{\n]*:\s*[^\{\n]*\bXCTestCase\b",
            sanitized,
        )
    )
    declaration = re.compile(
        r"\b(?:class|struct|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_.]*)[^\{]*\{"
    )
    swift_testing_suites: list[tuple[str, int, int]] = []
    for match in declaration.finditer(sanitized):
        opening = match.end() - 1
        closing = matching_brace(sanitized, opening)
        if closing is not None and re.search(r"@Test\b", sanitized[opening:closing]):
            swift_testing_suites.append((match.group(1), opening, closing))
    outer_suites = {
        name
        for name, opening, closing in swift_testing_suites
        if not any(
            other_opening < opening and closing < other_closing
            for _, other_opening, other_closing in swift_testing_suites
        )
    }
    return xctest_suites | outer_suites


def has_top_level_test(source: str) -> bool:
    sanitized = strip_comments_and_strings(source)
    declaration = re.compile(
        r"\b(?:class|struct|enum|actor|extension)\s+[A-Za-z_][A-Za-z0-9_.]*[^\{]*\{"
    )
    scopes: list[tuple[int, int]] = []
    for match in declaration.finditer(sanitized):
        opening = match.end() - 1
        closing = matching_brace(sanitized, opening)
        if closing is not None:
            scopes.append((opening, closing))
    return any(
        not any(opening < match.start() < closing for opening, closing in scopes)
        for match in re.finditer(r"@Test\b", sanitized)
    )


def infer_test_target(
    relative_path: Path, config: MappingConfig | None = None
) -> str | None:
    if config:
        path_text = relative_path.as_posix()
        for pattern, target in config.test_target_paths:
            if fnmatch.fnmatchcase(path_text, pattern):
                return target
    parts = relative_path.parts
    if len(parts) >= 3 and parts[0] == "Tests":
        return parts[1]
    for part in reversed(parts[:-1]):
        if part.endswith(("Tests", "UITests")):
            return part
    return None


def discover_test_files(repository: Path, config: MappingConfig) -> list[TestFile]:
    files: list[TestFile] = []
    candidates = decode_paths(
        run_git(
            repository,
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            "*.swift",
        )
    )
    for relative_name in candidates:
        relative_path = Path(relative_name)
        path = repository / relative_path
        if not path.is_file() or matches_any(
            relative_path.as_posix(), DEFAULT_IGNORES + config.ignore_paths
        ):
            continue
        target = infer_test_target(relative_path, config)
        if target is None:
            continue
        contents = path.read_text(encoding="utf-8")
        suites = parse_test_suites(contents)
        top_level_tests = has_top_level_test(contents)
        if suites or top_level_tests:
            files.append(
                TestFile(
                    str(relative_path),
                    target,
                    frozenset(suites),
                    top_level_tests,
                    contents,
                )
            )
    return files


DEFAULT_IGNORES = (
    ".build/**",
    ".swiftpm/**",
    "DerivedData/**",
    "Pods/**",
    "Carthage/**",
    "Generated/**",
    "**/Generated/**",
    "*.generated.swift",
    "**/*.generated.swift",
    "Package.resolved",
    "**/Package.resolved",
)

BUILD_CONFIGURATION_NAMES = {"Package.swift", "project.pbxproj"}
BUILD_CONFIGURATION_SUFFIXES = {".xcconfig", ".xcscheme", ".xctestplan"}


def matches_any(path: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def source_target_for_path(path: Path) -> str | None:
    parts = path.parts
    if len(parts) >= 3 and parts[0] == "Sources":
        return parts[1]
    return None


def source_declarations(repository: Path, relative_path: Path) -> set[str]:
    path = repository / relative_path
    if not path.is_file():
        return {relative_path.stem}
    source = strip_comments_and_strings(path.read_text(encoding="utf-8"))
    declarations = set(
        re.findall(
            r"\b(?:class|struct|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)",
            source,
        )
    )
    declarations.add(relative_path.stem)
    return declarations


def compress_identifiers(identifiers: set[str]) -> list[str]:
    targets = {identifier for identifier in identifiers if "/" not in identifier}
    return sorted(
        identifier
        for identifier in identifiers
        if "/" not in identifier or identifier.split("/", 1)[0] not in targets
    )


def map_changed_sources(
    repository: Path, paths: list[str], config: MappingConfig
) -> list[str]:
    """Map changes from most specific evidence to conservative target fallbacks.

    Changed test files and explicit mappings are authoritative. Production files
    then use filename and declaration-reference heuristics. When those heuristics
    cannot prove a suite mapping, source-target imports select dependent targets.
    Unknown ownership deliberately selects every discovered target.
    """
    test_files = discover_test_files(repository, config)
    suites_by_stem: dict[str, set[str]] = {}
    tests_by_path: dict[str, TestFile] = {}
    for test_file in test_files:
        suites_by_stem.setdefault(Path(test_file.path).stem, set()).update(
            test_file.identifiers
        )
        tests_by_path[test_file.path] = test_file
    identifiers: set[str] = set()
    all_targets = {test_file.target for test_file in test_files}
    for path in paths:
        if matches_any(path, DEFAULT_IGNORES + config.ignore_paths):
            continue
        explicit = {
            identifier
            for pattern, mapped_identifiers in config.source_mappings
            if fnmatch.fnmatchcase(path, pattern)
            for identifier in mapped_identifiers
        }
        if explicit:
            identifiers.update(explicit)
            continue
        changed = Path(path)
        if path in tests_by_path:
            identifiers.update(tests_by_path[path].identifiers)
            continue
        if (
            changed.name in BUILD_CONFIGURATION_NAMES
            or changed.suffix in BUILD_CONFIGURATION_SUFFIXES
        ):
            if not all_targets:
                raise RuntimeError(
                    f"'{path}' affects test configuration, but no test targets were discovered"
                )
            identifiers.update(all_targets)
            continue
        if changed.suffix != ".swift":
            continue
        changed_test_target = infer_test_target(changed, config)
        if changed_test_target is not None:
            identifiers.add(changed_test_target)
            continue

        specific = set(suites_by_stem.get(f"{changed.stem}Tests", set()))
        if not specific:
            declarations = source_declarations(repository, changed)
            for test_file in test_files:
                test_stem = Path(test_file.path).stem
                if any(
                    test_stem in {f"{name}Test", f"{name}Tests"}
                    or re.search(rf"\b{re.escape(name)}\b", test_file.contents)
                    for name in declarations
                ):
                    specific.update(test_file.identifiers)
        if specific:
            identifiers.update(specific)
            continue

        source_target = source_target_for_path(changed)
        dependent_targets: set[str] = set()
        if source_target:
            for mapped_source, mapped_targets in config.target_mappings:
                if mapped_source == source_target:
                    dependent_targets.update(mapped_targets)
            dependent_targets.update(
                test_file.target
                for test_file in test_files
                if source_target in test_file.imported_modules
            )
        if dependent_targets:
            identifiers.update(dependent_targets)
        elif all_targets:
            # Safe fallback: unknown ownership broadens to every discovered test
            # target so a heuristic miss cannot silently suppress relevant tests.
            identifiers.update(all_targets)
        else:
            raise RuntimeError(
                f"cannot map changed Swift file '{path}' because no test targets were discovered"
            )
    return compress_identifiers(identifiers)


def emit(identifiers: list[str], output_format: str) -> None:
    """Serialize canonical identifiers without mixing diagnostics into stdout."""
    if output_format == "list":
        if identifiers:
            print("\n".join(identifiers))
        return
    if output_format == "xcodebuild":
        if identifiers:
            print(
                "\n".join(f"-only-testing:{identifier}" for identifier in identifiers)
            )
        return
    if output_format == "swift":
        if identifiers:
            # SwiftPM matches a regular expression against its test specifiers.
            # Suite names keep the filter portable between XCTest's dotted
            # specifiers and Swift Testing's slash-separated identifiers.
            components = sorted(
                {identifier.rsplit("/", 1)[-1] for identifier in identifiers}
            )
            expression = "|".join(re.escape(component) for component in components)
            print(f"swift test --filter {shlex.quote(expression)}")
        return
    raise RuntimeError(f"unsupported output format: {output_format}")


LEGACY_DEPRECATION = (
    "warning: scripts/impacted_swift_tests.py is deprecated; use "
    "tools/impacted-swift-tests/impacted-swift-tests plan"
)


def _packaged_main(arguments: list[str]) -> int:
    package_source = Path(__file__).parents[1] / "tools" / "impacted-swift-tests" / "src"
    sys.path.insert(0, str(package_source))
    from impacted_swift_tests.cli import main as packaged_main

    return packaged_main(arguments)


def _legacy_package_arguments(arguments: list[str]) -> list[str]:
    translated = ["plan"]
    has_format = False
    force_list = False
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--dry-run":
            force_list = True
        elif argument == "--mapping-config":
            translated.append("--config")
            index += 1
            translated.append(arguments[index])
        elif argument.startswith("--mapping-config="):
            translated.append("--config=" + argument.partition("=")[2])
        elif argument == "--format":
            has_format = True
            translated.append(argument)
            index += 1
            format_name = arguments[index]
            translated.append(
                {"swift": "swiftpm-args", "xcodebuild": "xcodebuild-args"}.get(
                    format_name, format_name
                )
            )
        elif argument.startswith("--format="):
            has_format = True
            format_name = argument.partition("=")[2]
            translated.append(
                "--format="
                + {"swift": "swiftpm-args", "xcodebuild": "xcodebuild-args"}.get(
                    format_name, format_name
                )
            )
        else:
            translated.append(argument)
        index += 1
    if force_list or not has_format:
        translated.extend(["--format", "list"])
    return translated

def _legacy_compatibility_main(arguments: list[str]) -> int:
    compatibility_arguments = [
        argument
        for argument in arguments
        if argument != "--allow-repository-code-execution"
    ]
    parsed = parse_arguments(compatibility_arguments)
    repository = Path.cwd()
    try:
        paths = collect_changed_paths(repository, parsed)
        config = load_mapping_config(repository, parsed.mapping_config)
        identifiers = map_changed_sources(repository, paths, config)
        emit(identifiers, "list" if parsed.dry_run else parsed.format)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0



def main(argv: list[str] | None = None) -> int:
    command_arguments = sys.argv[1:] if argv is None else argv
    if command_arguments and command_arguments[0] == "plan":
        return _packaged_main(command_arguments)
    print(LEGACY_DEPRECATION, file=sys.stderr)
    packaged_stderr = io.StringIO()
    translated = _legacy_package_arguments(command_arguments)
    with contextlib.redirect_stderr(packaged_stderr):
        result = _packaged_main(translated)
    if (
        result in (2, 4)
        and "repository code execution requires --allow-repository-code-execution"
        not in packaged_stderr.getvalue()
    ):
        return _legacy_compatibility_main(command_arguments)
    sys.stderr.write(packaged_stderr.getvalue())
    return result


if __name__ == "__main__":
    raise SystemExit(main())
