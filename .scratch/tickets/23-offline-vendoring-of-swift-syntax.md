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
has to be told anything, so the parity decision holds unchanged. Built and measured end to end, not
argued: a prepared copy on that manifest builds and passes all 235 tests with no network access.

One thing this ticket decides but does not itself declare: the `.package(path: "../swift-syntax")`
line. `Package.swift` has no swift-syntax dependency yet, the three manifests have to stay at
parity, and `AGENTS.md` puts a target's declaration in the ticket that creates its sources. So the
route below is settled and its harness is built and tested, while the manifest line lands with the
parsing target. Everything written in the present tense about swift-syntax specifically is
conditional on that line; everything about swift-argument-parser and about the harness is live now.

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
  The root `Package.resolved` does not say so, because it has no swift-syntax entry at all yet.
- **How the pin stays aligned**: through `SyntaxGrammar.pinnedAlignmentSeries` rather than through
  a second literal. The harness reads that constant and accepts any `603.x.y` tag, because a patch
  release inside a series cannot add grammar; the manifest range the pin ticket specified,
  `"603.0.0"..<"604.0.0"`, lands with the parsing target and is derived from the same constant.
  Bumping the series stays the one edit that ticket described.
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
Alongside that it reads `pinnedAlignmentSeries` and rejects a swift-syntax checkout off that series.
That last check is the point of the ticket and it is deliberately inert today: it arms itself from
whatever `Package.local.swift` names, so it starts firing the moment the swift-syntax line lands
rather than needing to be remembered then.

Two bugs died with the rewrite. The toolchain gate demanded `Swift version 6.2` and would have
rejected every current machine; it is gone rather than retargeted, because vendored sources mean the
toolchain is not the grammar - plain parsing carries no toolchain lock, so pinning the toolchain to
the series would reject a newer one for no reason. The version is recorded in the output instead.
And the old script left swift-argument-parser as a remote dependency, so the "offline validation"
copy it produced still needed the network - it was never offline. The prepared copy now builds and
runs all 235 tests under `--disable-automatic-resolution`.

### What it costs

Measured on an Apple-silicon laptop under Swift 6.3.3, clean builds of `swift build --build-tests`,
with a throwaway parsing target depending on `SwiftParser`, `SwiftSyntax` and
`SwiftParserDiagnostics` standing in for the real one.

| | today | with swift-syntax vendored | delta |
|---|---|---|---|
| vendored checkouts | 3.3 MiB | 16.3 MiB | +13.0 MiB |
| `.build` | 238 MiB | 574 MiB | +336 MiB |
| clean build, wall | 11.3 s | 23.6 s | +12.3 s (2.1x) |
| clean build, CPU | 50.4 s | 138.6 s | +88.2 s (2.8x) |

The checkout is the cheap half and the question text's "much larger checkout" overstates it: a
shallow clone at the tag is 13 MiB against swift-argument-parser's 3.3 MiB, 4x rather than an order
of magnitude, and 11 MiB of that is working tree with 1.9 MiB of history. Build output is where the
cost actually lands, more than doubling `.build`. Wall time roughly doubles, in line with the ~21 s
the dependency posture ticket measured for a minimal SwiftParser executable, and CPU nearly
triples - swift-syntax parallelises well, so a machine with fewer cores pays closer to the CPU
figure than the wall one. None of this is paid on an incremental build.

The costs above are what the parsing target will add, not what it has added: they were measured by
standing a throwaway target up against a real vendored checkout, then taking it down. What the
parsing-target ticket inherits from here is one line in `Package.local.swift` -
`.package(path: "../swift-syntax")` beside the existing path dependency - and nothing else, because
the harness reads whatever path dependencies the manifest names.
