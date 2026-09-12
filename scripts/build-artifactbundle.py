#!/usr/bin/env python3
"""Build the `regression-guard` artifact bundle a release publishes.

The CLI is the only part of this repository with dependencies, and it lives in
its own nested package so those dependencies stay out of every consumer's graph.
Shipping the CLI prebuilt is what will let the published package offer the
`swift package regression-guard` plugin without dragging swift-syntax back in.

Produces a universal (arm64 + x86_64) bundle and prints the SwiftPM checksum for
`.binaryTarget(name:url:checksum:)`.
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
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path(".build/artifacts"))
args = parser.parse_args()

source = pathlib.Path(__file__).resolve().parents[1]
cli = source / "RegressionGuardCLI"
if not (cli / "Package.swift").exists():
    parser.error(f"{cli} is not a package")

build = ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"]
subprocess.run(build, cwd=cli, check=True)
built = pathlib.Path(
    subprocess.check_output(build + ["--show-bin-path"], cwd=cli, text=True).strip()
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
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(bundle), str(archive)], check=True)
checksum = subprocess.check_output(
    ["swift", "package", "compute-checksum", str(archive)], cwd=source, text=True
).strip()

print(bundle.resolve())
print(archive.resolve())
print(f"checksum {checksum}")
