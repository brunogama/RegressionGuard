Title: False-positive calibration
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 08-v1-rule-catalog-and-detection-shapes, 10-output-and-observer-surface

## Question

How should RegressionGuard measure and act on false-positive findings after rollout?

Resolve the feedback record, denominator, review labels, minimum sample size, and whether severity defaults may change automatically or only through an explicit maintainer decision. The mechanism must preserve finding evidence and avoid treating an unreviewed warning as a false positive.

## Resolution

Every reviewed finding records exactly one of three outcomes: confirmed shortcut, legitimate change, or inconclusive. The finding evidence, rule ID, confidence, severity, approval state, repository, and review reference remain attached to the outcome.

False-positive rate is calculated per rule from reviewed findings only: legitimate-change outcomes divided by confirmed-shortcut plus legitimate-change outcomes. Inconclusive and unreviewed findings are excluded from this rate, but unreviewed findings remain visible in review-completion counts.

A rule needs at least 20 reviewed findings before its rate can trigger a severity-review proposal. Calibration never changes shipped defaults automatically. A maintainer must review the evidence and approve a normal, auditable configuration or code change before a rule's default severity changes.
