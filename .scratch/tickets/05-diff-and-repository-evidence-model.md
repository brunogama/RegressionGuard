Title: Diff and repository evidence model
Labels: wayfinder:prototype
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 01-threat-model-and-failure-taxonomy

## Question

What evidence model should rules consume so they can detect lazy-agent regressions without creating fragile false positives?

Resolve the shape of the domain model: file diffs, hunks, old and new content, commit metadata, coverage reports, CI configuration changes, generated path classification, and rule output. A cheap prototype or outline is allowed if it helps choose the model.

## Resolution

Rules consume one unified `EvidenceBundle`. The bundle always carries the parsed file-level diff, hunk and line data, old and new content where available, path classification, and commit or pull-request context. Repository-wide measurements such as coverage, CI configuration changes, and generated-path evidence are optional typed sections of the same bundle.

Each rule declares the evidence signals it requires. Missing optional evidence must be explicit and degrade confidence or produce an inconclusive result; it must never be silently treated as a passing signal. Rule output remains a structured finding containing rule identity, severity, confidence, source path or repository scope, location when available, message, detail, and approval state.

This keeps one stable rule seam while allowing file-local and repository-wide checks to share evidence without pretending coverage is a property of an individual hunk. The prototype is preserved at `.scratch/prototypes/diff-evidence-model.html`.
