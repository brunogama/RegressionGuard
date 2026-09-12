Title: Coverage quality bar
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 01-threat-model-and-failure-taxonomy, 03-enforcement-policy-and-severity-model

## Question

How should the 90%+ coverage requirement apply in v1?

Resolve whether 90%+ is a quality gate for RegressionGuard's own package tests, a default policy for guarded repositories, a configurable repository-specific threshold, or some combination. The answer should decide what metric counts, how CI measures it, how regressions are reported, and whether the package blocks below-threshold coverage or only blocks coverage drops.

## Resolution

The 90%+ requirement is a hard quality gate for RegressionGuard's own package. Guarded repositories do not receive a universal default floor; they may configure an explicit floor from 70% through 100%.

Use overall line coverage from `llvm-cov export` as the v1 metric. The package gate blocks when head coverage is below the configured absolute floor or when the base-to-head drop exceeds the configured tolerance. This catches both an already-under-tested package and a newly introduced regression.

Coverage results are structured findings in the versioned CI report, including metric, base percentage, head percentage, absolute floor, allowed drop, observed drop, report identity, and repository scope. Human output and GitHub annotations may summarize the same finding without replacing the structured evidence.
