Title: Offline vendoring of swift-syntax
Labels: wayfinder:task
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

How does `Package.local.swift` resolve swift-syntax without network access?

Arises from the dependency posture decision, which treated offline build support as live. That manifest uses path dependencies (`../swift-argument-parser`) and is backed by `scripts/prepare-offline-validation.py`. swift-syntax is a much larger checkout than swift-argument-parser, and the syntax target needs it present for an offline build to produce a syntax-aware binary.

Do the work of vendoring it and record what the offline path now requires: where the checkout lives, which revision is pinned and how that pin stays aligned with the version range in `Package.swift`, what `prepare-offline-validation.py` must do differently, and how much disk and build time the offline route now costs. If offline builds turn out to be unable to carry syntactic evidence, say so plainly here, since the parity decision then requires telling those consumers rather than silently degrading them.

## Resolution

**Offline builds can carry syntactic evidence at full parity.** The route is a vendored source
checkout at `../swift-syntax`, on a tag in the alignment series
`SyntaxGrammar.pinnedAlignmentSeries` pins, reached through the same kind of path dependency
`Package.local.swift` already uses for swift-argument-parser. Nothing is degraded and no consumer
has to be told anything, so the parity decision holds unchanged. Demonstrated rather than argued: a
prepared copy builds and passes all 248 tests with no network access, and the grammar test in that
run asserts the offline build can name its own series.

Both manifests declare swift-syntax here rather than deferring it. That needed a target to consume
it, because a declared-but-unused dependency would make every consumer resolve swift-syntax for
nothing, so `RegressionGuardSyntax` lands with this ticket: the target ticket 14 placed behind the
CLI, holding swift-syntax so RegressionGuardKit stays dependency-free. It carries the source-text
half of the work - `SwiftSyntaxProjection`, which turns Swift source into the `SyntaxTree`
projection RegressionGuardKit owns, and `CompiledSyntaxGrammar`, which reports the series the build
resolved. The provider's other half, fetching base-ref source over git, is not here; that is
integration work with its own shape, and `SyntacticEvidenceProvider` stays unimplemented rather
than stubbed, because a provider that answered every request with `.unavailable` would be exactly
the `implementation_stubbed` shape this package exists to flag.

`Package.binary.swift` correctly gains nothing. It declares no package dependencies at all - every
target in it is a binary target or the plugin - and ticket 24 already accepted that a
binary-distributed run has no parser. Parity means all three manifests keep working, not that all
three carry swift-syntax.

The tempting alternative was measured and rejected. `prepare-offline-validation.py` used to strip
the swift-syntax package out of the manifest and compile against the toolchain's own host modules
at `usr/lib/swift/host`. That works further than expected: `Parser.parse`, `SourceLocationConverter`,
`SyntaxVisitor`, all four trivia comment cases and `ParseDiagnosticsGenerator` all compile and run
under Swift 6 language mode, and the 6.3.3 toolchain's copy parses `nonisolated(nonsending)` and
`[3 of Int]` clean. It fails on the one thing this project cannot give up. The toolchain ships no
`SwiftSyntax<series>` marker module - `canImport(SwiftSyntax603)` is false there and true against
the package - so the parsing target cannot report the series it was compiled against, which is
exactly the mechanism the version pin ticket settled on. A run with a working parser would emit a
report with no `syntaxGrammar`, indistinguishable from a run that had no parser at all. That is the
silent degradation `CONTEXT.md` forbids, so the host-module route is gone rather than kept as a
fallback. Two smaller marks against it, recorded because they would have surfaced later: the modules
are the compiler's private copy, ABI-named `CompilerSwiftSyntax` and package-named `Toolchain`, so
any `SyntaxKind` description reads `CompilerSwiftSyntax.SyntaxKind.functionDecl` and would differ
from an online build's text; and being private, they carry no compatibility promise.

### What the offline path requires

- **Where the checkout lives**: `../swift-syntax`, beside the repository, matching
  `../swift-argument-parser`. Vendoring needs the network and is therefore a before-you-go-offline
  step, not something the harness does.
- **Which revision**: the current series tag, `603.0.2` (`79e4b74a`). That is the revision the
  parse-performance harness resolved under the pinned range, and the same commit carries
  `swift-6.3.3-RELEASE`, so the offline grammar is the same one an online resolve produces today.
  A fresh online resolve against the new manifest range picks exactly that revision, so the vendored
  checkout and the resolver agree. That agreement is not recorded anywhere committed: this
  repository does not track `Package.resolved`, so no manifest-independent pin file exists for
  either route, online or offline.
- **How the pin stays aligned**: `Package.swift` declares the range the pin ticket specified,
  `"603.0.0"..<"604.0.0"`, and the harness reads `SyntaxGrammar.pinnedAlignmentSeries` and accepts
  any `603.x.y` tag, because a patch release inside a series cannot add grammar. The series is
  decided in that constant and written into the manifest beside it; bumping it stays the one edit
  ticket 24 described, now three lines instead of one. A fourth check is free and automatic:
  `CompiledSyntaxGrammar` reports the series the build actually resolved, and its test asserts that
  against the constant, so a manifest range that drifts from the pin fails the suite.
- **A path dependency records no pin.** `Package.resolved` never gets an entry for a path
  dependency - verified against a full offline build, which produced no `Package.resolved` at all -
  so the offline route has no resolver-enforced version and the checkout's own tag is the whole pin.
  That is why the harness verifies the series rather than trusting it.

### What `prepare-offline-validation.py` does differently

It no longer substitutes toolchain host modules for anything. It reads the path dependencies out of
`Package.local.swift`, refuses to proceed unless each vendored checkout is present, then copies the
repository and installs `Package.local.swift` as the copy's `Package.swift` with each `../name`
rewritten to the vendored absolute path - necessary because the destination is an arbitrary
directory, and because inside a git worktree `../` is not the developer's checkout root either.
Alongside that it reads `pinnedAlignmentSeries` and rejects a swift-syntax checkout off that series,
which is the check this ticket exists to install and which is live now that the manifest names
swift-syntax. It reads whatever path dependencies the manifest declares, so a future one is covered
without editing the harness.

Two bugs died with the rewrite. The toolchain gate demanded `Swift version 6.2` and would have
rejected every current machine; it is gone rather than retargeted, because vendored sources mean the
toolchain is not the grammar - plain parsing carries no toolchain lock, so pinning the toolchain to
the series would reject a newer one for no reason. The version is recorded in the output instead.
And the old script left swift-argument-parser as a remote dependency, so the "offline validation"
copy it produced still needed the network - it was never offline. The prepared copy now builds and
runs all 235 tests under `--disable-automatic-resolution`.

### Strictness is a manifest setting offline, not a command-line one

The offline route cannot be built with `swift build -Xswiftc -warnings-as-errors`, and this is a
property of path dependencies rather than anything swift-syntax introduced. SwiftPM suppresses
warnings only for dependencies it fetched itself, so a path dependency compiles with its warnings
visible, and a command-line `-Xswiftc` reaches every target in the graph. Measured on identical
sources: swift-argument-parser 1.8.2 as a remote dependency builds silently, while the same commit
as a path dependency raises four `_errorLabel` deprecation errors under that flag. No SwiftPM
option scopes `-Xswiftc` to the root package, so the flag cannot stay on the command line.

The prepared copy therefore carries `-warnings-as-errors -strict-concurrency=complete` on its own
targets, appended to the manifest, where `package.targets` already means exactly this repository's
targets and nothing else. That is what CI means by the flags: our code compiles warning-free. It is
deliberately not a relaxation dressed up as a fix, and both halves were checked - a warning planted
in `RegressionGuardKit` fails the offline build as an error, while the vendored checkouts' own 16
warnings stay visible and non-fatal rather than being suppressed.

`.unsafeFlags` is fine here and only here. It would make a package unusable as a versioned
dependency, but it is written into the disposable copy rather than into `Package.local.swift`, so
the tracked manifests stay publishable and stay mirrors of each other. Swift 6.1's
`.treatAllWarnings(as:)` would express this without `.unsafeFlags`, but it needs a tools-version
bump past the 6.0 `AGENTS.md` fixes, which raises the SwiftPM floor for every consumer - too much
to spend on a validation harness.

### What it costs

Measured on an Apple-silicon laptop under Swift 6.3.3, clean `swift build --build-tests` of a
prepared offline copy, before and after this change - so "after" is the real `RegressionGuardSyntax`
target and its test target, not an estimate.

| | before | after | delta |
|---|---|---|---|
| vendored checkouts | 3.3 MiB | 16.3 MiB | +13.0 MiB |
| `.build` | 238 MiB | 623 MiB | +385 MiB |
| clean build, wall | 11.3 s | 34.4 s | +23.1 s (3.0x) |
| clean build, CPU | 50.4 s | 188.7 s | +138.3 s (3.7x) |

The checkout is the cheap half and the question text's "much larger checkout" overstates it: a
shallow clone at the tag is 13 MiB against swift-argument-parser's 3.3 MiB, 4x rather than an order
of magnitude, and 11 MiB of that is working tree with 1.9 MiB of history. Build output is where the
cost actually lands, more than doubling `.build`. Wall time roughly doubles, in line with the ~21 s
the dependency posture ticket measured for a minimal SwiftParser executable, and CPU nearly
triples - swift-syntax parallelises well, so a machine with fewer cores pays closer to the CPU
figure than the wall one. None of this is paid on an incremental build.

These are floors, not ceilings. The rule migrations and the AST-only families will add source to
`RegressionGuardSyntax`, and the provider's git half is still to come, so the wall figure will grow
from 34 s rather than settle there. The shape holds though: it is swift-syntax that costs, and it
costs once per clean build.
