Title: Nested CLI package layout
Labels: wayfinder:task
Status: closed
Assignee: none
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

How does a consumer stop paying for the CLI's dependencies?

The dependency posture decision put parsing behind the CLI so RegressionGuardKit would stay
dependency-free, and it does. What that decision did not account for is that SwiftPM resolves the
whole package graph regardless of which product a consumer uses, so a dependency-free *target* in a
package that has dependencies is not a dependency-free *consumer*.

Measured against the README's headline consumer - `GoldenMaster` in a test target, "only needed if
you use golden-master snapshots" - on a cold cache:

| | |
|---|---|
| objects fetched | 80,542 |
| checkouts carried | 13.5 MiB (12 swift-syntax, 1.5 Commander) |
| compile cost | zero; only GoldenMaster, MyApp and the test target are built |

Resolution works and the build is correct, so nothing is broken. The cost is fetch and disk, paid
by every consumer of a snapshot-testing library for a CLI they never build. That contradicts what
`README.md` promises about the install.

Resolve the package layout that removes it, and record what the move costs.

## Proposed resolution

Adopt swift-syntax's own layout: a nested package for the CLI, beside the published root package
rather than inside it. That repository ships four of them - `CodeGeneration`, `Examples`,
`SwiftParserCLI`, `SwiftSyntaxDevUtils` - and `SwiftParserCLI/Package.swift` is this exact case,
declaring `.package(path: "..")` plus the CLI-only dependency its root manifest must not carry.

The mechanism is verified rather than assumed, and by a measurement already in hand: the
GoldenMaster consumer above resolved `commander` and `swift-syntax` and **not**
`swift-argument-parser`, which swift-syntax's nested CLI package depends on. A nested package's
dependencies do not reach consumers of the root.

### Target layout

| | root `Package.swift` | `CLI/Package.swift` |
|---|---|---|
| products | `GoldenMaster`, `RegressionGuardKit`, `RegressionGuardObserver`, `RegressionGuardPlugin` | `regression-guard`, `regression-guard-observer` |
| targets | the three library targets | `regression-guard`, observer CLI, `RegressionGuardSyntax`, `RegressionGuardCommandLine` |
| dependencies | none | `.package(path: "..")`, Commander, swift-syntax |
| consumer cost | zero | never resolved |

### What this retires

- `Package.source.swift` disappears. The nested CLI package *is* the source build, so the manifest
  added to keep source building possible alongside a binary CLI is no longer needed.
- `Package.local.swift` collapses into the CLI package. Only the CLI has dependencies, so only the
  CLI needs an offline variant, and a nested package can switch on an environment variable the way
  `SwiftParserCLI` does with `SWIFTCI_USE_LOCAL_DEPS`. That is a legitimate use of an env-var
  manifest precisely because no consumer ever resolves it - the objection that killed the idea for
  the published manifest does not apply here.
- `Package.binary.swift` should go with them. It describes a distribution that was never produced,
  and the root manifest under this layout delivers what it was for.

### The open decision: the command plugin

`swift package regression-guard` needs the CLI in the consumer's graph, and a nested package cannot
supply it. Two answers, and this ticket does not pick one:

1. **Keep the plugin in the root, pointed at a `binaryTarget`.** `scripts/build-artifactbundle.py`
   already produces the artifact - universal, 8.0 MiB zipped, verified to run. Binary artifacts are
   downloaded **eagerly**, now measured rather than assumed: a consumer package using only an
   unrelated library target still downloaded a 72 MiB artifact bundle in full before building. So
   this costs every consumer the 8 MiB, not only the ones who run the plugin.
2. **Move the plugin into the CLI package.** Zero consumer cost, but this does not merely make the
   plugin opt-in - it removes it. A nested package is not addressable by URL, because SwiftPM
   resolves a package from a repository root, so a consumer cannot depend on `CLI/` at all. The
   plugin would be reachable only by cloning this repository.

So the real trade is 8 MiB on every consumer against deleting a documented feature for all of them,
which is a product decision rather than a technical one. Note that (1) still beats today on every
axis - 8 MiB downloaded against 80,542 objects fetched and 13.5 MiB of checkouts - and matches the
ecosystem norm; SwiftLint ships its plugin exactly this way, which is what the measurement above
was taken against.

A third architecture escapes the trade entirely and should be weighed before either: **put the CLI
in its own repository** rather than nesting it. Consumers of the libraries then pay literally
nothing, the CLI package stays addressable by URL so the plugin survives and stays opt-in, and
`Vendor/` leaves this repository with it. The cost is two repositories to release in step.

## Migration steps

1. Create `CLI/Package.swift` declaring `.package(path: "..")`, Commander, and swift-syntax.
2. Move `Sources/regression-guard`, `Sources/RegressionGuard/ObserverCLI`,
   `Sources/RegressionGuardSyntax`, and `Sources/RegressionGuardCommandLine` under `CLI/Sources/`.
3. Move `Tests/RegressionGuardSyntaxTests` under `CLI/Tests/`.
4. Move the two files in `Tests/RegressionGuardKitTests` that are coupled to the CLI, and only
   those two. Established by inspection rather than assumed, because the suite's names mislead
   here: `EnforcementWeakeningEndToEndTests` is the sole file that spawns
   `.build/debug/regression-guard`, and `AdvisoryRuleAdoptionTests` is the sole file that reads a
   CLI source file from disk (`Sources/regression-guard/InitCommand.swift`, for the default config
   it asserts on). `EndToEndScratchRepoTests` sounds like a third and is not - it drives
   `RegressionGuardRunner` through `@testable import RegressionGuardKit` and spawns nothing, so it
   stays with the root package.
5. Move `Vendor/` and the offline manifest into the CLI package. Only the CLI has dependencies, so
   only the CLI vendors anything, and the root package having none is the point of this layout
   rather than a temporary state - keeping a shared `Vendor/` at the root would be reserving a
   place for a need the design says will not arise. Note this does not change what consumers
   download either way: git clones the whole repository, so the 3.2 MiB of bare repositories ships
   to every consumer regardless of which directory holds it. Only moving the CLI to its own
   repository removes that.
6. Update `scripts/prepare-offline-validation.py`, `scripts/build-artifactbundle.py`, the `Justfile`
   recipes, `ci.yml`, and `regression-guard-self-check.yml` for two package roots.
7. Update `README.md`: the install promise, the repository layout section, and the plugin section
   according to the plugin decision above.
8. Delete `Package.source.swift` and `Package.binary.swift`.

## Acceptance

- A consumer package depending on the root and using only `GoldenMaster` resolves **zero**
  dependencies, measured on a cold cache with `--cache-path`.
- Both packages build and test under the repository's strict flags.
- The offline route still builds and tests with no network, verified against an empty cache.
- The plugin decision is recorded, with its consumer cost measured rather than estimated.

## Risks

- **Test-target split.** Step 4 moves tests between packages, and a test silently lost in the move
  is exactly the regression this project exists to catch. The count must be reconciled across both
  packages afterwards: 248 today. The split is smaller than it first looked - two files, not a
  whole suite - but the two were found by grepping for `Process()` and for reads of
  `Sources/regression-guard`, so a third coupling introduced before this lands would be missed by
  anyone repeating the step from memory rather than repeating the grep.
- **Two package roots in CI.** Every workflow, script, and recipe that assumes one package root has
  to be found. A missed one fails loudly, so this is tedious rather than dangerous.
- **The root package keeps a plugin whose executable lives elsewhere**, under option (1). That is an
  unusual shape and needs a comment saying why, or the next reader will try to "fix" it.
- **This does not reduce what the guard itself costs to build** - the CLI still compiles
  swift-syntax. It moves who pays, not how much.

## Resolution

The split shipped. The root package is the published one and declares **no dependencies at all**;
everything with a dependency lives in `RegressionGuardCLI/`, a nested package, named after
swift-syntax's own `SwiftParserCLI` rather than the bare `CLI/` this ticket proposed, so the
directory says which package it holds.

| | root `Package.swift` | `RegressionGuardCLI/Package.swift` |
|---|---|---|
| products | `GoldenMaster`, `RegressionGuardKit`, `RegressionGuardObserver` | `regression-guard`, `regression-guard-observer`, `RegressionGuardPlugin` |
| dependencies | none | `..`, swift-syntax, Commander |
| tests | 234 | 14 |

Measured against the same cold-cache consumer this ticket opened with - a test target using only
`GoldenMaster`:

| | before | after |
|---|---|---|
| objects fetched | 80,542 | 0 |
| checkouts carried | 13.5 MiB | none |
| `Package.resolved` | written | not written |
| cache after resolve | 67 MiB | 52 KiB |

`swift build` and `swift test` pass in both packages, `just offline` still builds and tests with no
network, and the test count reconciles: 234 + 14 = 248, the number this ticket recorded before the
move. `EnforcementWeakeningEndToEndTests` needed no code change - its `#filePath` walk lands on the
CLI package root, which is where the binary it spawns now builds. `AdvisoryRuleAdoptionTests` moved
back to the root package: it reads a CLI source file but needs `TestSupport`, so only its path
string changed.

Three things the migration steps did not anticipate:

- **A path dependency takes its identity from the directory name.** `.package(path: "..")` made the
  parent's identity `feat+swift-syntax` in a worktree, and would do the same in a fork or any clone
  the user renamed. `.package(name: "RegressionGuard", path: "..")` fixes the identity in the
  manifest.
- **Strict flags had to move into the CLI manifest.** `-Xswiftc -warnings-as-errors` on the command
  line reaches dependencies too, and SwiftPM only suppresses dependency warnings for packages it
  fetched itself - so offline, where they resolve locally, upstream's own deprecations failed a
  build this repository cannot fix. `.unsafeFlags` is safe there and only there, because no
  consumer resolves a nested package.
- **`Vendor/` is a git data structure, not text.** The whitespace hooks rewrote `packed-refs`,
  stripping the trailing space git writes on its header line. `prek.toml` now excludes
  `RegressionGuardCLI/Vendor/` from all three text hooks.

### The plugin: option (2), as an interim state

The plugin lives in `RegressionGuardCLI/` today, which means it is reachable only by cloning this
repository. That is not the intended end state and should not be read as one. Option (1) - the root
declaring `.binaryTarget(url:checksum:)` against the artifact bundle - is the destination, and
`scripts/build-artifactbundle.py` already produces it: universal arm64 + x86_64, 8.0 MiB zipped,
checksum printed. It cannot be declared yet because `url:` needs a published release to point at,
and a checksum cannot be computed for an artifact that does not exist at a URL.

So the order is forced rather than chosen: cut a release carrying the bundle, then move the plugin
back to the root behind the binary target. Until then the documented `swift package regression-guard`
verb is unavailable to consumers, and that is the cost of landing this ticket before a release
exists.

The eager-download measurement stands and decides the destination: a consumer using only an
unrelated library target still downloaded a 72 MiB bundle in full. Option (1) therefore costs every
consumer 8 MiB, not only the ones who run the plugin - still far better than 80,542 objects and
13.5 MiB of checkouts, and the same shape SwiftLint ships.

The separate-repository idea is not taken. It would cost nothing at all, but it buys that by making
two repositories release in step, and the artifact bundle already gets the plugin to zero marginal
resolution cost for consumers who never invoke it.

### Superseded

`Package.local.swift`, `Package.source.swift`, and `Package.binary.swift` are deleted, along with
`scripts/prepare-offline-validation.py`. The offline switch is one environment variable,
`REGRESSIONGUARD_OFFLINE`, read by the CLI manifest - a legitimate use precisely because no
consumer resolves that manifest. This supersedes the parts of ticket 23's resolution that name
those files.
