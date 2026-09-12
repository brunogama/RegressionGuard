Title: Enforcement policy and severity model
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 01-threat-model-and-failure-taxonomy, 02-existing-guardrails-research

## Question

How should v1 map each failure category to configurable enforcement outcomes?

Resolve the policy model for hard failures, warnings, approval-required findings, and informational evidence. The answer should decide default severities, how repository owners override them, and which categories must never be silently downgraded without an explicit exception.

## Resolution

V1 uses a balanced enforcement model: high-confidence shortcut regressions block by default; heuristic findings remain advisory; and informational findings provide evidence without affecting acceptance.

Default blocking families are test suppression, assertion weakening, enforcement weakening, review escape, unapproved baseline drift, and the RegressionGuard package's own coverage floor below 90%. Behavior deletion, error-handling collapse, and guarded-repository coverage drops within the configured tolerance are advisory by default.

Repository owners may change a rule's outcome only through an explicit, auditable configuration exception. Hard-failure rules are not silently downgraded.

An approval marker records that a protected change was intentional but does not erase the finding. The CLI exits nonzero only for findings at or above `--fail-on`, with `error` as the default threshold.
