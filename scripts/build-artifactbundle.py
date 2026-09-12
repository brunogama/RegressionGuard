#!/usr/bin/env python3
"""Build the `regression-guard` artifact bundle that consumers resolve instead of source.

The CLI is the only part of this package with dependencies. Shipping it as a
binary keeps them out of every consumer's dependency graph: a project that wants
`GoldenMaster` for snapshot tests resolves nothing at all, rather than fetching
swift-syntax and Commander for a CLI it never builds.

Produces a universal (arm64 + x86_64) bundle and prints the SwiftPM checksum to
put in `.binaryTarget(name:url:checksum:)`.
"""
from __future__ import annotations
import argparse
import json
import pathlib
import shutil
import subprocess

EXECUTABLES = ["regression-guard", "regression-guard-observer"]

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--version", required=True, help="Release version, for example 0.1.0")
parser.add_argument(
    "--manifest",
    default="Package.source.swift",
    help="Manifest to build the CLI from; the shipping one declares it as a binary",
)
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path(".build/artifacts"))
args = parser.parse_args()

source = pathlib.Path(__file__).resolve().parents[1]
manifest = source / args.manifest
if not manifest.exists():
    parser.error(f"{manifest} not found")

# Build from the source manifest, in a scratch copy so the shipping `Package.swift` is untouched.
scratch = source / ".build/artifactbundle-source"
if scratch.exists():
    shutil.rmtree(scratch)
scratch.mkdir(parents=True)
for entry in ["Sources", "Plugins", "Tests", "Vendor"]:
    if (source / entry).exists():
        shutil.copytree(source / entry, scratch / entry, symlinks=True)
shutil.copy2(manifest, scratch / "Package.swift")

subprocess.run(
    ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"],
    cwd=scratch,
    check=True,
)
built = pathlib.Path(
    subprocess.check_output(
        ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64",
         "--show-bin-path"],
        cwd=scratch,
        text=True,
    ).strip()
)

bundle = args.output / "regression-guard.artifactbundle"
if bundle.exists():
    shutil.rmtree(bundle)
artifacts = {}
for name in EXECUTABLES:
    variant = f"{name}-{args.version}-macos"
    destination = bundle / variant / "bin"
    destination.mkdir(parents=True)
    shutil.copy2(built / name, destination / name)
    artifacts[name] = {
        "version": args.version,
        "type": "executable",
        "variants": [
            {
                "path": f"{variant}/bin/{name}",
                "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"],
            }
        ],
    }

(bundle / "info.json").write_text(
    json.dumps({"schemaVersion": "1.0", "artifacts": artifacts}, indent=2) + "\n"
)

archive = args.output / "regression-guard.artifactbundle.zip"
if archive.exists():
    archive.unlink()
subprocess.run(
    ["ditto", "-c", "-k", "--keepParent", str(bundle), str(archive)],
    check=True,
)
checksum = subprocess.check_output(
    ["swift", "package", "compute-checksum", str(archive)], cwd=source, text=True
).strip()

print(bundle.resolve())
print(archive.resolve())
print(f"checksum {checksum}")
