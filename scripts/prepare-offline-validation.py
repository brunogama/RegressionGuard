#!/usr/bin/env python3
"""Create a disposable validation copy that builds with no network access.

Every dependency `Package.local.swift` names is a bare git repository committed
under `Vendor/`, so there is nothing to fetch and nothing to vendor first. This
copies the repository and installs that manifest as the copy's `Package.swift`.

The copy carries CI's strict flags on its own targets, so build it plainly:
`swift build --build-tests` and `swift test`. Do not add
`-Xswiftc -warnings-as-errors` on the command line - that reaches the vendored
repositories too, and their own deprecations would fail a build this repository
cannot fix.

The shipping Package.swift is NOT changed. This is not a distributable build and
cannot verify remote dependency resolution or macOS/Xcode integration.
"""
from __future__ import annotations
import argparse
import pathlib
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=pathlib.Path, help="New, nonexistent validation directory")
args = parser.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
if args.destination.exists():
    parser.error("destination must not already exist")

swift = shutil.which("swift")
if not swift:
    parser.error("swift not found")
# Recorded, not gated. Plain parsing carries no toolchain lock, so the toolchain does not have to
# match the series: the vendored repository is the grammar, and the toolchain only has to build it.
version = subprocess.check_output([swift, "--version"], text=True)

manifest_text = (source / "Package.local.swift").read_text()
vendored = re.findall(r'\.package\(\s*url:\s*"Vendor/([^"]+)\.git"', manifest_text)
if not vendored:
    parser.error("Package.local.swift declares no vendored repositories")
for name in vendored:
    if not (source / "Vendor" / f"{name}.git" / "HEAD").exists():
        parser.error(f"vendored repository missing at {source / 'Vendor' / (name + '.git')}")

# Each vendored repository is referenced as local source control, so the resolver reads its tags
# and enforces the declared version - a copy off the pinned series fails to resolve rather than
# quietly building the wrong grammar. What the resolver cannot see is the declared range drifting
# from the constant the rules are written against, so that is checked here.
grammar = (source / "Sources/RegressionGuardKit/Syntax/SyntaxGrammar.swift").read_text()
series_match = re.search(r"pinnedAlignmentSeries\s*=\s*(\d+)", grammar)
if not series_match:
    parser.error("could not read pinnedAlignmentSeries from SyntaxGrammar.swift")
series = int(series_match.group(1))
declared = re.search(r'\.package\(\s*url:\s*"Vendor/swift-syntax\.git",\s*"(\d+)\.', manifest_text)
if not declared:
    parser.error("Package.local.swift does not declare the vendored swift-syntax repository")
if int(declared.group(1)) != series:
    parser.error(
        f"Package.local.swift pins swift-syntax series {declared.group(1)}, but "
        f"SyntaxGrammar.pinnedAlignmentSeries says {series}"
    )

shutil.copytree(
    source,
    args.destination,
    # `Package.resolved` is dropped deliberately. It belongs to `Package.swift`, which pins the
    # dependencies to their upstream URLs, and carrying it into a copy whose manifest resolves the
    # vendored repositories instead sends SwiftPM to the network for pins the copy does not use.
    ignore=shutil.ignore_patterns(
        ".build", ".git", ".swiftpm", "__pycache__", "Package.resolved"
    ),
)

# CI's strictness, applied in the manifest rather than on the command line, because the two are not
# the same thing here. `swift build -Xswiftc -warnings-as-errors` reaches every target it compiles,
# including the vendored repositories - and SwiftPM only suppresses warnings for dependencies it
# fetched itself, so a locally resolved dependency's own deprecations become this build's errors.
# There is no SwiftPM flag that scopes the CLI option, so the copy carries the flags on its own
# targets, where they mean what CI means by them: this repository's code compiles warning-free.
manifest_text += """

// OFFLINE VALIDATION ONLY: CI's strict flags, scoped to this package's own targets.
for target in package.targets where target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"])
    ]
}
"""
(args.destination / "Package.swift").write_text(manifest_text)

print(args.destination.resolve())
print(version.strip())
print(f"pinned swift-syntax alignment series {series}")
for name in vendored:
    repository = source / "Vendor" / f"{name}.git"
    revision = subprocess.check_output(
        ["git", "-C", str(repository), "rev-parse", "HEAD"], text=True
    ).strip()
    tags = subprocess.check_output(
        ["git", "-C", str(repository), "tag", "--points-at", "HEAD"], text=True
    ).split()
    releases = [tag for tag in tags if re.fullmatch(r"v?\d+\.\d+\.\d+", tag)]
    print(f"{name} {revision} {' '.join(releases)}")
