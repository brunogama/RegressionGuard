Title: Approval and exception surface
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 01-threat-model-and-failure-taxonomy, 03-enforcement-policy-and-severity-model

## Question

Where should intentional risky changes be approved, and what evidence should the approval require?

Resolve whether approval lives in commit messages, PR body, configuration, inline suppressions, or a combination. Decide the exact approval marker semantics, audit trail requirements, and which shortcuts cannot be approved inline.

## Resolution

Intentional risky changes may be approved through either the commit-message range or the pull request body. Configuration defines the policy and allowed scopes, but does not silently approve an individual change.

Use a structured, scope-bearing marker such as `regression-guard:approve <rule-or-scope>`. Matching should be exact and auditable rather than a case-insensitive substring found in arbitrary prose.

An approved finding remains visible in CI output and is marked approved; approval allows the check to pass without erasing the evidence. High-confidence findings cannot be suppressed inline. Inline suppression is reserved for localized heuristic findings and must remain visible to reviewers.
