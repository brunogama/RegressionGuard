# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-12

First release.

### Added

- `regression-guard check`, which compares two refs - or a ref and the working tree - and reports
  changes that route around a failing test instead of fixing it: disabled or skipped tests,
  weakened assertions, deleted behaviour, collapsed error handling, drifting golden masters,
  coverage regressions, and weakened enforcement configuration.
- Syntactic evidence. Files a rule asks for are parsed with swift-syntax and projected into
  `RegressionGuardKit`'s own `SyntaxTree`, so detection reads structure rather than diff lines. A
  side that cannot be read is a reported gap, never a silent pass, and a run names the grammar it
  judged with.
- Three rule families that only structure makes possible, all advisory: `known_issue_suppression`,
  `implementation_stubbed`, `unreachable_assertion`.
- `GoldenMaster`, a dependency-free library for recording and verifying behaviour snapshots, with
  the `golden_master_drift` rule requiring an approval marker before a baseline may move.
- `regression-guard-observer`, which turns a report into a versioned observation artifact carrying
  per-rule totals, review outcomes and false-positive rates, so severity changes rest on evidence.
- `regression-guard coverage`, comparing two `llvm-cov export` reports against a maximum drop.
- `regression-guard init`, writing a default `.regressionguard.yml`.
- A GitHub composite action, and workflow templates for consumer repositories.
- A universal (arm64 and x86_64) artifact bundle, which
  [RegressionGuardPlugin](https://github.com/brunogama/RegressionGuardPlugin) resolves to provide
  `swift package regression-guard`.

### Notes

- The published package has no dependencies at all. Everything with one - the CLI, its parser, and
  their vendored sources - lives in `RegressionGuardCLI/`, a nested package no consumer resolves,
  so a project using only `GoldenMaster` resolves nothing and writes no `Package.resolved`.
- The CLI's dependencies are committed as bare repositories under `RegressionGuardCLI/Vendor/`, so
  it builds and tests with no network.

[Unreleased]: https://github.com/brunogama/RegressionGuard/compare/0.1.0...HEAD
[0.1.0]: https://github.com/brunogama/RegressionGuard/releases/tag/0.1.0
