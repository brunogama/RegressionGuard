#!/usr/bin/env python3
"""Create a disposable validation copy using Swift's installed host libraries.

The shipping Package.swift is NOT changed. This is not a distributable build and
cannot verify remote dependency resolution or macOS/Xcode integration.
"""
from __future__ import annotations
import argparse
import pathlib
import shutil
import subprocess
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=pathlib.Path, help="New, nonexistent validation directory")
args = parser.parse_args()
source = pathlib.Path(__file__).resolve().parents[1]
if args.destination.exists():
    parser.error("destination must not already exist")
swift = shutil.which("swift")
if not swift:
    parser.error("swift not found")
version = subprocess.check_output([swift, "--version"], text=True)
if "Swift version 6.2" not in version:
    parser.error("This offline harness requires a Swift 6.2.x toolchain")
host = pathlib.Path(swift).resolve().parents[1] / "lib" / "swift" / "host"
if not (host / "SwiftSyntax.swiftmodule").is_dir():
    parser.error(f"SwiftSyntax host modules not found at {host}")
shutil.copytree(source, args.destination, ignore=shutil.ignore_patterns(".build", ".git", ".swiftpm", "__pycache__"))
manifest = args.destination / "Package.swift"
text = manifest.read_text()
text = "\n".join(line for line in text.splitlines() if not (
    '.package(url: "https://github.com/swiftlang/swift-syntax.git"' in line
    or '.product(name: "SwiftSyntax", package:' in line
    or '.product(name: "SwiftParser", package:' in line
    or '.product(name: "SwiftParserDiagnostics", package:' in line
))
host_literal = json.dumps(str(host))
text += f'''\n
// OFFLINE VALIDATION ONLY: uses installed toolchain modules, not the pinned package.
for target in package.targets where target.type != .plugin {{
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags(["-I", {host_literal}])]
    target.linkerSettings = (target.linkerSettings ?? []) + [.unsafeFlags([
        "-L", {host_literal}, "-Xlinker", "-rpath", "-Xlinker", {host_literal}
    ])]
}}
'''
manifest.write_text(text)
print(args.destination.resolve())
print(version.strip())
