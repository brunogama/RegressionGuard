Title: Swift-syntax dependency posture
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

Where does the swift-syntax dependency live in the package, and what does taking it on cost every consumer?

RegressionGuardKit is a published library product with exactly one dependency today (swift-argument-parser). Resolve whether swift-syntax is a direct dependency of RegressionGuardKit, a separate target that RegressionGuardKit depends on, or a separate target only the CLI depends on.

The decision must account for the CLI, the PackagePlugin execution wrapper, and both alternate manifests (`Package.local.swift` and `Package.binary.swift`), since a binary-distributed artifact and a source-built one carry a package dependency very differently.

## Resolution

Parsing lives in a dedicated target that only the CLI depends on. RegressionGuardKit keeps zero package dependencies and owns the rule logic plus the syntactic-evidence types; the new target owns swift-syntax and produces parsed evidence the runner supplies to rules. This is the only arrangement that keeps `Package.binary.swift` working, because that manifest ships RegressionGuardKit as an XCFramework binary target, and a binary target cannot declare package dependencies. It also matches the evidence model settled while charting: rules declare the evidence they need rather than fetching it themselves.

Build cost was measured rather than assumed. A clean build with a warm package cache of a minimal SwiftParser plus SwiftSyntax executable takes 21.1s wall and 62s CPU on an Apple-silicon laptop, against roughly 14s for RegressionGuard's own full `build --build-tests`. swift-syntax roughly doubles a cold build and is invisible on an incremental one. This ticket originally asserted swift-syntax was "substantially heavier to build"; that was folklore, and the question text above has been corrected. Build cost is not a reason to keep swift-syntax out of any target. The binary manifest is.

All three manifests stay at parity. A binary consumer receiving weaker detection than a source consumer would be precisely the silent evidence gap `CONTEXT.md` forbids, where missing evidence becomes an implicit pass. If binary distribution cannot carry syntactic evidence, consumers must be told explicitly rather than quietly downgraded.

The version floor is `from: "600.0.0"` with a range permitting 601 and later. Pure parsing does not require the swift-syntax version to match the host toolchain; that lock-step discipline applies to macro use. This premise is being confirmed by Swift-syntax capability research and must be revised if that ticket contradicts it.

Offline build support is treated as live rather than vestigial, so vendoring swift-syntax for `Package.local.swift` becomes its own ticket.

## Amendment

The version-floor clause in the resolution above is superseded by Swift-syntax capability research.

Two findings break it. First, `from:` does not float across alignment series: a manifest declaring `from: "600.0.0"` resolves to 600.0.1, not to the current 603.0.2, because each language alignment is a new major. "A range permitting 601 and later" is therefore not something `from:` can express, and the pin is a maintained decision rather than a resolver outcome. Second, an under-selected version does not fail loudly; swift-syntax cannot represent syntax newer than itself, so new constructs land in unexpected nodes and rules stop seeing them. That is a silent degradation into a pass, which is the one outcome this project forbids.

The toolchain-lock premise itself held: 600.0.1 built and ran correctly under a 6.4 toolchain. Only the mechanism and the choice of floor were wrong.

Target ownership and manifest parity are unaffected and remain decided. Selecting the pin is now its own decision, tracked in Swift-syntax version pin and grammar coverage.
