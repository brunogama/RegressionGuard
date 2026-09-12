Title: Rule extension surface
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 05-diff-and-repository-evidence-model, 08-v1-rule-catalog-and-detection-shapes

## Question

How should repository-specific rules extend RegressionGuard in v1?

Resolve whether rules should be compiled Swift types, PackagePlugin extensions, configuration-only declarations, or a deliberate mix. The decision must preserve the unified EvidenceBundle contract, independent rule identities, deterministic output, and safe CI execution without turning configuration into arbitrary code execution.

## Resolution

V1 uses compiled built-in Swift rules with configuration-only tuning for enablement, severity, thresholds, paths, and approval policy. The PackagePlugin remains an execution wrapper that invokes the CLI; it is not a dynamic rule-discovery or rule-loading API.

This keeps rule behavior reviewable, deterministic, and safe in CI. Configuration must not execute arbitrary code or define a second incompatible evidence model. A future public Rule protocol or plugin extension can be proposed separately once the stable EvidenceBundle and CI report contracts have shipped.
