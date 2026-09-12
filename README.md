# GoldenMasterSwift

Two things, meant to be added to any Swift project:

1. **`GoldenMaster`** — a golden-master (characterization) snapshot testing library. Record what
   your code actually does today; fail the build the moment it silently does something else.
2. **`RegressionGuard`** — a CI check that catches the specific shortcuts a coding agent (or a
   tired human) reaches for when it gets stuck on a failing test, instead of actually fixing the
   underlying bug:
   - disabling or skipping a test (`XCTSkip`, `.disabled(...)`, commenting the test out)
   - deleting or weakening an assertion (`XCTAssertTrue(true)`, deleting the test file)
   - deleting the production code path that was failing, instead of fixing it (force-unwraps
     replacing real error handling, empty `catch` blocks, ripped-out branches)
   - letting a recorded `GoldenMaster` baseline drift, or line coverage regress, without anyone
     noticing

This is not a linter for style. It is a linter for *cheating*.

## Why

Agentic coding tools are very good at making a red CI check turn green. They are not always
careful about *how*. Left alone, the path of least resistance is often: comment out the failing
assertion, `throw XCTSkip(...)`, delete the branch that throws, force-unwrap past the crash. All
of those make the pipeline pass without fixing anything. `regression-guard` runs on every diff and
fails the build when it sees that pattern, so it has to be caught in review instead of merged.

## Install

Add the package as a dependency:

```swift
.package(url: "https://github.com/<your-org>/GoldenMasterSwift", from: "0.1.0")
```

And to the targets that need it:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: ["GoldenMaster"] // only needed if you use golden-master snapshots
)
```

## GoldenMaster: recording behavior instead of asserting it

```swift
import GoldenMaster

@Test func rendersInvoiceHTML() throws {
    let html = InvoiceRenderer().render(sampleInvoice)
    try GoldenMaster.verify(html)
}
```

The first run has nothing to compare against and throws `GoldenMasterMissing`. Record the
baseline once:

```sh
GM_RECORD=1 swift test --filter rendersInvoiceHTML
```

That writes `Sources/.../__GoldenMasters__/rendersInvoiceHTML.snapshot.txt` next to the test file.
Commit it. From then on, `verify` fails the test the moment the output changes, and the PR shows
the *exact* behavior diff as an ordinary file diff — no more, no less than a normal code review.

Works with any `Encodable` value (recorded as sorted-key pretty-printed JSON), `String`, `Data`, or
your own type via `GoldenMasterSnapshottable`. Use `identifier:` when one test records more than
one snapshot.

`RegressionGuard`'s `golden_master_drift` rule flags any change under `__GoldenMasters__/` that
doesn't carry the configured approval marker in a commit message — so an *intentional* baseline
update still needs a human to say so out loud, and an agent silently re-recording a baseline to
dodge a failure gets caught.

## RegressionGuard: the CI check

### As a CLI

```sh
swift run regression-guard check --base origin/main --head HEAD
```

```sh
regression-guard check [--base <ref>] [--head <ref>] [--path <dir>] [--format text|json|github] [--report-file <path>] [--fail-on info|warning|error]
regression-guard coverage --base-report base.json --head-report head.json [--max-drop-percent 0.5]
regression-guard init   # writes a default .regressionguard.yml
```

regression-guard-observer --report-file report.json [--outcomes-file outcomes.json] [--output-file observation.json]

Omit `--head` to check the working tree (uncommitted changes) against `--base` — handy as a local
JSON reports include stable finding IDs, evidence references, approval state, and a short deterministic
`remediation` hint when the rule has one. Hints name only a safe repair direction derived from the
finding category - they never prescribe a patch or suggest weakening tests, thresholds, or review.

`regression-guard-observer` preserves every stable finding ID in a versioned observation artifact.
`outcomes.json` may map IDs to legacy outcome strings such as `"confirmed"`, or to an
object with `outcome` and an optional durable `reference`. Omitted IDs stay visibly unreviewed.
Each artifact carries the source repository and adds per-rule totals, explicit review counts, outcome counts,
a false-positive rate (`legitimate / (confirmed + legitimate)`), and the 20-review threshold.
Qualification only proposes later maintainer review. Any severity change requires explicit maintainer
approval and is never automatic.

pre-commit habit before an agent's changes even get committed. Note: the function-level checks
(e.g. "a test lost its `@Test` attribute") read committed blobs via `git show`, so they only see
uncommitted content when `--head` is a real ref; line-based checks work either way.

### As a SwiftPM plugin (local, one command)

```sh
swift package regression-guard --base origin/main
```

### As a GitHub Action (CI, one line)

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0 # required so both commits are available to diff

- uses: <your-org>/GoldenMasterSwift/.github/actions/regression-guard@main
  with:
    fail-on: error
```

See `templates/consumer-workflow-example.yml` for a complete workflow file, and
`.github/actions/regression-guard/action.yml` for all inputs.

### Coverage regression

`regression-guard coverage` compares two `llvm-cov export` JSON reports:

```sh
swift test --enable-code-coverage
xcrun llvm-cov export .build/debug/MyAppPackageTests.xctest/Contents/MacOS/MyAppPackageTests \
  -instr-profile .build/debug/codecov/default.profdata -format=text > head.json
# ...repeat against the base ref's build...
regression-guard coverage --base-report base.json --head-report head.json --max-drop-percent 0.5
```

## Configuring what gets flagged

Run `regression-guard init` (or copy `templates/.regressionguard.yml`) to get a
`.regressionguard.yml` at your repo root:

```yaml
version: 1
approvalMarker: "regression-guard:approve"

rules:
  disabled_or_skipped_test: { enabled: true, severity: error }
  weakened_assertion:       { enabled: true, severity: error }
  behavior_deletion:        { enabled: true, severity: warning }
  error_handling_collapse:  { enabled: true, severity: warning }
  enforcement_weakening:    { enabled: true, severity: error }
  review_escape:            { enabled: true, severity: error }
  golden_master_drift:      { enabled: true, severity: warning }
  coverage_regression:      { enabled: true, severity: error }
ignore:
  - "**/.build/**"
  - "**/Generated/**"

testPaths:
  - "Tests/**"
  - "**/*Tests.swift"
```

`production_code_deletion` remains a legacy configuration alias for both `behavior_deletion` and
`error_handling_collapse`; new configuration should use the two separate rule IDs above.

An equivalent `.regressionguard.json` is also supported and is the more forgiving option if you
hit the limits of the intentionally small, dependency-free YAML reader (it expects consistent
2-space indentation and the shape above; it is not a general YAML parser).

Any otherwise-flagged change is allowed through if a commit message in the checked range contains
the `approvalMarker` string — that's the escape hatch for genuinely intentional changes (updating
a baseline, deleting a truly obsolete test), and it leaves a paper trail in the git log for why.

## Rules reference

| Rule ID | Default severity | Catches |
|---|---|---|
| `disabled_or_skipped_test` | error | `XCTSkip`, `.disabled(...)`, `@Disabled`, a test losing its `test...`/`@Test` identity, commented-out test code, a whole test file deleted |
| `weakened_assertion` | error | assertions removed without replacement, tautological replacements (`XCTAssertTrue(true)`), a deleted test file's assertions going unchecked |
| `behavior_deletion` | warning | a validation branch or other behavior is removed without a plausible replacement |
| `error_handling_collapse` | warning | force-unwraps replacing safe unwrapping, empty/swallowing `catch` blocks, or removed error handling |
| `enforcement_weakening` | error | disabled RegressionGuard rules, removed CI test commands or SwiftPM test targets, and new SwiftLint disabled-rule configuration |
| `review_escape` | error | meaningful changes moved into ignored or generated paths |
| `golden_master_drift` | warning | a recorded `__GoldenMasters__` snapshot changing without the approval marker |
| `coverage_regression` | error | overall line coverage dropping beyond `--max-drop-percent` between base and head |

## Architecture

```
Sources/
  GoldenMaster/          snapshot recording/verification library
  RegressionGuardKit/    git diff parsing, path classification, rules, config, formatters
  regression-guard/      CLI (swift-argument-parser)
  RegressionGuardPlugin/ `swift package regression-guard` command plugin
Tests/
  GoldenMasterTests/
  RegressionGuardKitTests/  unit tests per rule + an end-to-end scratch-git-repo test that
                            simulates an agent disabling a test and asserts it gets caught
.github/
  actions/regression-guard/ composite action for consumer repos
  workflows/                this repo's own CI + self-check (dogfoods the tool on its own PRs)
templates/                   copy-paste starting points for a consumer repo
```

`RegressionGuardKit` is a plain library with no XCTest/Xcode dependency, so it's usable from your
own tooling too (a pre-commit hook, a bot, a different CLI) — `regression-guard`'s CLI is a thin
wrapper around `RegressionGuardRunner`.

## Known limitations (v1)

- Detection is diff/regex/heuristic-based, not a full Swift AST analysis (no SwiftSyntax
  dependency, so no toolchain-version coupling) — it will miss cleverly disguised cheating and can
  occasionally flag a legitimate refactor. Treat violations as "a human should look at this," not
  as ground truth; the `approvalMarker` escape hatch exists for exactly that reason.
- `behavior_deletion` and `error_handling_collapse` are the least precise rules by nature (both
  default to `warning`, not `error`) — tune their thresholds or disable them per-repo if noisy.
- Working-tree checks (`--head` omitted) don't see uncommitted content for the function-level
  comparisons described above.
