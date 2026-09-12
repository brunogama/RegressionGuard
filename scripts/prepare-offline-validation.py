#!/usr/bin/env python3
"""Create a disposable validation copy that builds with no network access.

`Package.local.swift` resolves every dependency from a sibling checkout, so the
offline route is vendored source, not the toolchain's own libraries. This copies
the repository, installs that manifest as the copy's `Package.swift` with each
path dependency rewritten to the vendored checkout it names, and refuses to
proceed unless every checkout is present and swift-syntax sits on the alignment
series `SyntaxGrammar.pinnedAlignmentSeries` pins.

Vendoring itself needs the network and is therefore not done here; a missing
checkout is reported with the clone command that supplies it.

The copy carries CI's strict flags on its own targets, so build it plainly:
`swift build --build-tests` and `swift test`. Do not add
`-Xswiftc -warnings-as-errors` on the command line - that reaches the vendored
checkouts too, and their own deprecations would fail a build this repository
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

CLONE_URLS = {
    "swift-syntax": "https://github.com/swiftlang/swift-syntax.git",
    "Commander": "https://github.com/steipete/Commander.git",
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=pathlib.Path, help="New, nonexistent validation directory")
parser.add_argument(
    "--vendor-root",
    type=pathlib.Path,
    help="Directory holding the vendored checkouts (default: the repository's parent)",
)
args = parser.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
vendor_root = (args.vendor_root or source.parent).resolve()
if args.destination.exists():
    parser.error("destination must not already exist")

# The series is the pin. A patch release inside a series cannot add grammar, so the offline
# checkout only has to be on the right series, and bumping `pinnedAlignmentSeries` moves this
# check and the manifest's version range together.
grammar = (source / "Sources/RegressionGuardKit/Syntax/SyntaxGrammar.swift").read_text()
series_match = re.search(r"pinnedAlignmentSeries\s*=\s*(\d+)", grammar)
if not series_match:
    parser.error("could not read pinnedAlignmentSeries from SyntaxGrammar.swift")
series = int(series_match.group(1))

swift = shutil.which("swift")
if not swift:
    parser.error("swift not found")
# Recorded, not gated. Plain parsing carries no toolchain lock, so the toolchain does not have to
# match the series: the vendored checkout is the grammar, and the toolchain only has to build it.
version = subprocess.check_output([swift, "--version"], text=True)

manifest_text = (source / "Package.local.swift").read_text()
dependencies = re.findall(r'\.package\(\s*path:\s*"\.\./([^"]+)"\s*\)', manifest_text)
if not dependencies:
    parser.error("Package.local.swift declares no path dependencies to vendor")

# swift-syntax is vendored in-tree as a bare repository, so the resolver enforces the declared
# range against its tags and a copy off the series fails to resolve. What the resolver cannot see
# is the range drifting from the constant the rules are written against, so that is checked here.
vendored_syntax = source / "Vendor/swift-syntax.git"
if not (vendored_syntax / "HEAD").exists():
    parser.error(f"vendored swift-syntax repository missing at {vendored_syntax}")
declared = re.search(
    r'\.package\(\s*url:\s*"Vendor/swift-syntax\.git",\s*"(\d+)\.', manifest_text
)
if not declared:
    parser.error("Package.local.swift does not declare the vendored swift-syntax repository")
if int(declared.group(1)) != series:
    parser.error(
        f"Package.local.swift pins swift-syntax series {declared.group(1)}, but "
        f"SyntaxGrammar.pinnedAlignmentSeries says {series}"
    )

revisions = {}
for name in dependencies:
    checkout = vendor_root / name
    if not (checkout / ".git").exists():
        hint = f"  git clone --depth 1 {CLONE_URLS[name]} {checkout}" if name in CLONE_URLS else ""
        parser.error(
            f"vendored checkout missing at {checkout}\n"
            f"  vendor it while you still have network:\n{hint}"
        )
    tags = subprocess.check_output(
        ["git", "-C", str(checkout), "tag", "--points-at", "HEAD"], text=True
    ).split()
    # Release tags only. The same commit also carries prerelease and toolchain-snapshot tags, and
    # neither names a version. The `v` prefix is optional because the vendored checkouts disagree
    # about it: swift-syntax tags `603.0.2` and Commander tags `v0.2.4`.
    releases = [tag for tag in tags if re.fullmatch(r"v?\d+\.\d+\.\d+", tag)]
    revisions[name] = (
        subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
        ).strip(),
        releases,
    )
    if name == "swift-syntax" and not any(tag.startswith(f"{series}.") for tag in releases):
        # An under-selected grammar does not fail loudly at runtime: swift-syntax cannot represent
        # syntax newer than itself, so rules stop seeing constructs and the change passes. The pin
        # is the defence, so a checkout off the series has to fail here instead.
        parser.error(
            f"{checkout} is on {', '.join(releases) or 'no release tag'}, "
            f"not alignment series {series}\n"
            f"  check out a {series}.x.y tag there, then re-run"
        )

shutil.copytree(
    source,
    args.destination,
    # `Package.resolved` is dropped deliberately. It belongs to `Package.swift`, which pins
    # swift-syntax to its upstream URL, and carrying it into a copy whose manifest resolves the
    # vendored repository instead sends SwiftPM to the network for a pin the copy does not use.
    ignore=shutil.ignore_patterns(
        ".build", ".git", ".swiftpm", "__pycache__", "Package.resolved"
    ),
)
# The copy can live anywhere, so `../name` would no longer find the vendored checkout.
for name in dependencies:
    manifest_text = manifest_text.replace(f'"../{name}"', f'"{vendor_root / name}"')

# CI's strictness, applied in the manifest rather than on the command line, because the two are not
# the same thing here. `swift build -Xswiftc -warnings-as-errors` reaches every target it compiles,
# including the vendored checkouts - and SwiftPM only suppresses warnings for dependencies it
# fetched itself, so a path dependency's own deprecations become this build's errors. There is no
# SwiftPM flag that scopes the CLI option, so the copy carries the flags on its own targets, where
# they mean what CI means by them: this repository's code compiles warning-free.
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
for name, (revision, tags) in revisions.items():
    print(f"{name} {revision} {' '.join(tags)}")
