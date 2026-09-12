#!/usr/bin/env python3
"""Exercise the real CLI; optionally run both SwiftPM plugins in a temporary consumer."""
from __future__ import annotations
import argparse
import json
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", type=pathlib.Path, required=True)
parser.add_argument("--plugins", action="store_true")
parser.add_argument("--timeout", type=int, default=900, help="Per-command timeout in seconds (default: 900)")
args = parser.parse_args()
if args.timeout < 1:
    parser.error("--timeout must be positive")
binary = args.binary.resolve()
if not binary.is_file():
    parser.error(f"CLI binary does not exist: {binary}")
package = pathlib.Path(__file__).resolve().parents[1]
checks = 0

def run(command: list[str], *, cwd: pathlib.Path | None = None, expected: int = 0) -> subprocess.CompletedProcess[str]:
    global checks
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=args.timeout)
    if result.returncode != expected:
        raise AssertionError(f"Expected {expected}, got {result.returncode}: {command}\n{result.stdout}\n{result.stderr}")
    checks += 1
    return result

def cli(*arguments: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
    return run([str(binary), *arguments], expected=expected)

with tempfile.TemporaryDirectory(prefix="scma-smoke-") as directory:
    root = pathlib.Path(directory)
    sources = root / "source folder"
    sources.mkdir()
    source = sources / "Source File.swift"
    source.write_text("class C { var value = 0; func f(_ n: Int) { if n > 0 { value = n } } }\n")
    cli("--help")
    cli("--version")
    cli("analyze", str(sources), "--unknown", expected=2)
    cli("analyze", str(sources), "--format", expected=2)
    cli("analyze", str(sources), "--format", "json", "--format", "text", expected=2)
    cli("analyze", str(sources), "--jobs", "0", expected=2)
    first = cli("analyze", str(sources), "--format=json", "--jobs", "1")
    second = cli("analyze", str(sources), "--format=json", "--jobs", "4")
    assert first.stdout == second.stdout
    report = json.loads(first.stdout)
    assert report["complete"] and len(report["metrics"]) == 10
    assert report["overallScore"] is None
    assert report["inputFiles"] == ["Source File.swift"]
    cli("analyze", str(sources), "--threshold", "CCF=1", "--fail-on-violation", expected=1)
    diagnostic = cli("analyze", str(sources), "--threshold", "CCF=1", "--format", "diagnostics")
    assert "warning: SCMA [CCF]" in diagnostic.stdout
    for format_name in ("json", "csv", "html", "text"):
        output = root / "reports" / f"report.{format_name}"
        result = cli("analyze", str(sources), "--format", format_name, "--output", str(output))
        assert output.is_file() and not result.stdout
    cli("analyze", str(sources), "--output", str(source), expected=2)
    cli("analyze", str(sources), "--config", str(root / "missing.json"), expected=2)
    source.write_text("class Broken {")
    skipped = json.loads(cli("analyze", str(sources), "--format", "json").stdout)
    assert skipped["complete"] and skipped["analyzedFileCount"] == 0
    assert any("File skipped" in d["message"] for d in skipped["diagnostics"])
    invalid = cli("analyze", str(sources), "--format", "json", "--strict", expected=2)
    assert not json.loads(invalid.stdout)["complete"]

    if args.plugins:
        consumer = root / "PluginConsumer"
        demo = consumer / "Sources" / "Demo"
        demo.mkdir(parents=True)
        (consumer / "Package.swift").write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "PluginConsumer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "SwiftSCMA", path: {json.dumps(str(package))})],
    targets: [.target(name: "Demo", plugins: [.plugin(name: "SCMABuildPlugin", package: "SwiftSCMA")])]
)
''')
        demo_source = demo / "Demo.swift"
        demo_source.write_text("public struct Demo { public func f(_ n: Int) -> Int { if n > 0 { return n }; return 0 } }\n")
        missing_configuration = run(["swift", "build", "-j", "2"], cwd=consumer, expected=1)
        assert "requires" in missing_configuration.stdout + missing_configuration.stderr
        config = consumer / ".scma.json"
        config.write_text("{}")
        run(["swift", "build", "-j", "2"], cwd=consumer)
        stamps = list((consumer / ".build").rglob("SCMA.analysis.swift"))
        assert len(stamps) == 1, stamps
        stamp = stamps[0]
        # SwiftPM may finish host/destination tool relinking on the first follow-up
        # build. Warm that graph before asserting a stable no-op build.
        run(["swift", "build", "-j", "2"], cwd=consumer)
        before = stamp.stat().st_mtime_ns
        run(["swift", "build", "-j", "2"], cwd=consumer)
        assert stamp.stat().st_mtime_ns == before, "Warmed no-op build unexpectedly reran analysis"
        demo_source.write_text(demo_source.read_text() + "// changed source input\n")
        run(["swift", "build", "-j", "2"], cwd=consumer)
        assert stamp.stat().st_mtime_ns > before, "Source edit did not invalidate analysis"
        # Configuration existed at planning time and must now invalidate the command.
        config.write_text(json.dumps({"typeScope": "nominals", "thresholds": {"CCF": 1}, "failOnViolation": True}))
        failed = run(["swift", "build", "-j", "2"], cwd=consumer, expected=1)
        assert "warning: SCMA [CCF]" in failed.stdout + failed.stderr
        config.write_text(json.dumps({"typeScope": "nominals", "thresholds": {"CCF": 1}, "failOnViolation": False}))
        run(["swift", "build", "-j", "2"], cwd=consumer)
        command = run(["swift", "package", "scma", "--target", "Demo", "--format", "json"], cwd=consumer)
        package_report = json.loads(command.stdout)
        assert package_report["modules"] == ["Demo"]
        assert package_report["inputFileCount"] == 1
        run(["swift", "package", "scma", "--target", "missing"], cwd=consumer, expected=1)
        run(["swift", "package", "scma", "--target"], cwd=consumer, expected=1)
print(f"PASS: {checks} subprocess checks; CLI formats, deterministic output, failures, safety" + (", and both plugins/incrementality" if args.plugins else ""))
