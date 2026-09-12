Title: Existing guardrails research
Labels: wayfinder:research
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: none

## Question

What existing tools, papers, platform features, or open-source packages already address lazy-agent regression behavior, CI diff guardrails, test weakening, coverage regression, or suspicious code deletion?

Resolve this by collecting sourced findings and turning them into decisions this package can use: which ideas to copy, which to avoid, what vocabulary to adopt, and what gaps RegressionGuard should uniquely cover. This is AFK research.

## Resolution

Research is captured in [existing-guardrails-research.md](../research/existing-guardrails-research.md), backed by DeepAPI request `f2fbac01-88a8-4686-8830-b1fa328168da` and primary documentation scrape `7b0a54d9-8b7c-4bed-b58b-f6bed561c0e7`.

The package should integrate with required CI status checks rather than replace them; use explicit pass/warn/fail evidence; treat new-code and diff evidence as first-class; separate absolute coverage floors from patch/regression coverage; require reviewable approval for snapshot baseline updates; and keep v1 focused on deterministic shortcut-regression shapes rather than broad intent inference.

RegressionGuard's distinctive gap is same-change suppression and assertion-strength regression, including review escapes through ignored/generated paths and agent-oriented remediation evidence.
