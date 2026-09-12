Title: RegressionGuard agent laziness guardrail map
Labels: wayfinder:map
Status: open
Assignee: none

## Destination

Find the way to a configurable, CI-wired Swift package that detects and blocks agent laziness regressions across tests, production behavior, and enforcement configuration. This map may carry planning, implementation, and CI wiring when the route is clear, but each open ticket still resolves one decision or prerequisite.

## Notes

- Domain: Swift CI guardrail package for detecting lazy or risky agent-authored diffs.
- Standing threat model: disabling or weakening tests, removing or oversimplifying production behavior, weakening CI/lint/config enforcement, and escaping review through generated or ignored paths.
- Enforcement posture: configurable per rule from day one, with high-confidence shortcuts eligible for hard failure and lower-confidence heuristics eligible for warning or explicit approval.
- Quality bar: v1 implementation should sustain at least 90% line coverage for the package itself; guarded repositories may configure an explicit 70%-100% floor and regression-drop tolerance.
- Consult skills during work: grilling, domain-modeling, tdd, swiftlint-budget-enforcer, swift-testing, swift-concurrency when implementation starts.
- Tracker: local Markdown under `.scratch/tickets/`; child relationship is the `Parent:` line and blocking uses `Blocked by:`.
- Naming rule: refer to tickets by title in human-facing summaries, with links when useful.

## Decisions so far

- [CI integration and observation workflow](06-ci-integration-and-observation-workflow.md): keep check and coverage commands, add a versioned JSON report file, retain annotations and summaries for presentation, distinguish policy exit 1 from operational exit 2, and observe CI and review streams separately.
- [Coverage quality bar](07-coverage-quality-bar.md): enforce 90%+ line coverage for RegressionGuard itself; allow guarded repositories to configure an explicit 70%-100% floor; block below the configured floor or beyond the allowed base-to-head drop; report structured coverage evidence.
- [V1 rule catalog and detection shapes](08-v1-rule-catalog-and-detection-shapes.md): ship all eight families as separate stable rule IDs; block concrete high-confidence signals and keep behavior deletion/error collapse advisory.
- [Diff and repository evidence model](05-diff-and-repository-evidence-model.md): rules consume one unified EvidenceBundle with explicit optional repository-wide evidence and structured confidence degradation.
- [Approval and exception surface](04-approval-and-exception-surface.md): approve through commit or PR context with exact scoped markers; keep approved evidence visible; forbid inline suppression of high-confidence findings.
- [Enforcement policy and severity model](03-enforcement-policy-and-severity-model.md): high-confidence shortcut regressions block by default; heuristic findings are advisory; exceptions are explicit and auditable; CLI failure follows `--fail-on`.
- [Existing guardrails research](02-existing-guardrails-research.md): integrate with deterministic CI status checks, separate project and patch coverage, and focus RegressionGuard on diff-level shortcut regressions existing tools miss.
- [Threat model and failure taxonomy](01-threat-model-and-failure-taxonomy.md): v1 detects shortcut regressions across eight families, with confidence-ranked enforcement boundaries and broad intent inference out of scope.

- [Rule extension surface](09-rule-extension-surface.md): v1 uses compiled built-in Swift rules with configuration-only tuning; the PackagePlugin is an execution wrapper, not a dynamic loader.
- [Output and observer surface](10-output-and-observer-surface.md): keep text, JSON, GitHub, and Markdown outputs stable; use a separate Swift observer with stable evidence IDs and retain raw failure artifacts.
- [False-positive calibration](11-false-positive-calibration.md): record confirmed, legitimate, or inconclusive outcomes; calculate per-rule rates from reviewed findings; require 20 reviewed samples; require maintainer approval for severity changes.
- [Agent remediation prompt](12-agent-remediation-prompt.md): include deterministic, evidence-bounded repair hints while forbidding suggestions that weaken tests, thresholds, or visibility.

## Route clear

All design and decision tickets are resolved. Implementation may proceed from the ordered delivery plan.

## Out of scope

- Replacing human code review entirely; this map is for regression guardrails and evidence, not total semantic review.
- Detecting every possible bad simplification by intent; this map focuses on observable diff shapes and repository signals.
