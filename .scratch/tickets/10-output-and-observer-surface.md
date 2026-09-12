Title: Output and observer surface
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 06-ci-integration-and-observation-workflow, 09-rule-extension-surface

## Question

How should RegressionGuard package local output, CI annotations, and observer inputs beyond GitHub Actions?

Resolve which outputs are stable v1 contracts: text, JSON report, GitHub annotations, Markdown summaries, raw evidence artifacts, and host-neutral observer data. Decide whether the observer is a separate script or only a documented integration surface, and ensure output remains deterministic and useful for repairing failures without embedding host-specific behavior in core rules.

## Resolution

Text, JSON report, GitHub annotations, and Markdown summaries are all stable v1 output contracts. JSON remains the durable evidence format, while the other channels must present the same findings without silently dropping advisory, approved, or inconclusive results.

Observation lives in a separate Swift script rather than inside the core CLI or rules. It consumes the versioned report, workflow and pull-request metadata, failed-step logs, and review deltas, then emits deterministic repair-oriented summaries. Core rules remain host-neutral and do not query GitHub.

Reports preserve schema and tool versions, run identity, refs, deterministic finding IDs, evidence references, approval state, confidence, and remediation text. CI retains raw diff and coverage evidence artifacts on failure while keeping the structured report compact.
