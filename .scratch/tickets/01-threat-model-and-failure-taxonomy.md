Title: Threat model and failure taxonomy
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: none

## Question

What is the v1 threat model for agent laziness, and how should observed failure modes be grouped by confidence?

Resolve this by deciding the canonical categories for the package, including test weakening, production behavior deletion or simplification, enforcement weakening, generated or ignored path escapes, and any categories that should be explicitly excluded from v1. The answer should define the names future tickets use and rank each category as high-confidence, medium-confidence, or low-confidence.

## Resolution

V1 uses the following canonical shortcut regression families: test suppression, assertion weakening, behavior deletion, error handling collapse, enforcement weakening, coverage regression, review escape, and snapshot or baseline drift.

Confidence ranking: high confidence for test suppression, assertion weakening, enforcement weakening, review escape, snapshot or baseline drift, and coverage regression; medium confidence for error handling collapse; low to medium confidence for behavior deletion because legitimate refactors often delete code.

Out of scope for v1: detecting that code "got too simple" without a concrete diff pattern, product-quality regressions requiring semantic or domain understanding, performance regressions without benchmark evidence, and style or architecture complaints already covered by lint or review.

Canonical domain term: shortcut regression.
