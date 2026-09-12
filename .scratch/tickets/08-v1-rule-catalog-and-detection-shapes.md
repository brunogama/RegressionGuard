Title: V1 rule catalog and detection shapes
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 01-threat-model-and-failure-taxonomy, 05-diff-and-repository-evidence-model

## Question

Which concrete rules belong in v1, and what exact diff or repository signals should each rule detect?

Resolve the first rule catalog using the shortcut regression families from Threat model and failure taxonomy. For each candidate rule, decide its family, evidence inputs, default confidence, expected false positives, and whether it should ship in v1 or stay out of scope.

## Resolution

V1 ships one independently configurable rule per canonical shortcut-regression family. Each rule consumes the unified `EvidenceBundle`, declares required signals, emits a structured finding, and has its own stable rule ID, confidence, severity default, and approval behavior.

| Family | V1 signal | Confidence | Default posture |
| --- | --- | --- | --- |
| Test suppression | Added skip/disabled markers, commented-out test bodies, deleted test files, or lost test identity | High | Block |
| Assertion weakening | Assertions removed without replacement or replaced by tautologies | High | Block |
| Behavior deletion | Lopsided removal of production control-flow or validation logic without replacement | Low to medium | Advisory |
| Error handling collapse | Empty catches, newly ignored failures, force unwraps, or guarded error paths replaced by unchecked paths | Medium | Advisory |
| Enforcement weakening | Concrete weakening in known guard configs: CI workflows, lint/test configuration, RegressionGuard configuration, and package target declarations | High when concrete | Block |
| Coverage regression | Aggregate line coverage below the configured floor or beyond the allowed base-to-head drop | High | Block |
| Review escape | Meaningful changes moved into ignored/generated paths or otherwise removed from the guarded path set | High when path evidence is clear | Block |
| Snapshot/baseline drift | Added, changed, or deleted characterization baselines without the exact scoped approval marker | High | Block unless approved |

Behavior deletion and error handling collapse must be separate rules even where an implementation shares helper code. This keeps findings explainable and lets repositories tune their advisory policies independently. Legitimate refactors remain the primary false-positive risk for those two advisory families; concrete test suppression, enforcement weakening, review escape, coverage regression, and unapproved baseline drift are expected to be low-ambiguity signals.

The existing production detector should therefore be split into the behavior-deletion and error-handling-collapse rule identities. Coverage remains a repository-level rule with its own report input rather than pretending that an aggregate metric belongs to one file hunk.
