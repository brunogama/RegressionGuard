# Existing guardrails research

Ticket: [Existing guardrails research](../tickets/02-existing-guardrails-research.md)

DeepAPI requests:

- Deep research: `f2fbac01-88a8-4686-8830-b1fa328168da`
- Website evidence scrape: `7b0a54d9-8b7c-4bed-b58b-f6bed561c0e7`

## Executive synthesis

RegressionGuard should not position itself as a replacement for established CI quality gates, static analysis, mutation testing, or PR policy engines. Existing tools already cover generic merge blocking, coverage thresholds, security/static-analysis findings, and custom PR rules. RegressionGuard's gap is narrower: detecting **shortcut regressions** in the diff itself, especially when the same change weakens the evidence that normal CI relies on.

## Findings

### Required checks are the merge-control substrate

GitHub status checks already provide the general merge-blocking mechanism: required checks on protected branches must pass before a pull request can merge. The docs also warn that a skipped job reports `Success` and will not block merging even if it is required. RegressionGuard should therefore run as a real required check and should also detect changes that make checks skip, soften, or disappear.

Source: GitHub Docs, Status checks - <https://docs.github.com/en/pull-requests/reference/status-checks>

### Coverage services already model project and patch thresholds

Codecov's commit-status model distinguishes project coverage from patch coverage. Project status compares overall project coverage against the base of the pull request or parent commit. Patch status measures only lines adjusted in the pull request and indicates how well the pull request is tested. It also has `target`, `threshold`, and `informational` settings. RegressionGuard should copy the split between absolute package quality and patch/regression quality, but avoid becoming a coverage SaaS.

Source: Codecov Docs, Status Checks - <https://docs.codecov.com/docs/commit-status>

### Quality-gate products validate the value of new-code gates

SonarQube quality gates are a direct precedent for configurable policy gates. A gate is a set of conditions measured during analysis, defined on new code or overall code, and pass/fail output tells developers whether to fix or merge. RegressionGuard should copy the new-code focus and explicit pass/fail conditions, but keep its rule evidence local, inspectable, and diff-shaped.

Source: SonarQube Server Docs, Understanding quality gates - <https://docs.sonarsource.com/sonarqube-server/latest/quality-standards-administration/managing-quality-gates/introduction-to-quality-gates/>

### PR policy engines prove custom diff rules are common

Danger runs repository-specific `Dangerfile` rules during code review and can fail or warn on pull request properties. Its examples include PR-size warnings, assignment rules, and app-code/test-code relationships, and the ecosystem includes coverage plugins. RegressionGuard should copy the "rules close to the repo" ergonomics, but ship opinionated shortcut-regression rules instead of requiring every team to write them from scratch.

Source: Danger JS - <https://danger.systems/js/>

### Static analyzers cover security and pattern findings, not shortcut intent

Semgrep's CI integration runs scans on push and pull request events and sends findings for triage and remediation. This is useful precedent for CI deployment and finding presentation, but it addresses known code patterns and security/static-analysis rules. RegressionGuard's differentiated value is comparing old and new evidence, not just scanning the new tree.

Source: Semgrep Docs, Add Semgrep to CI - <https://semgrep.dev/docs/semgrep-ci/overview>

### Snapshot/golden workflows already require reviewable baseline updates

Deno snapshot testing documents the exact review loop RegressionGuard should emulate: if a pull request changes output, CI fails, the author updates snapshots locally and commits the new `.snap` files, and reviewers see before-and-after output in the PR diff. RegressionGuard should generalize this principle: baseline drift is acceptable only when explicit, reviewable, and approved.

Source: Deno Docs, Snapshot testing - <https://docs.deno.com/runtime/test/snapshots/>

### Mutation testing is the research-backed analog for assertion weakness

PIT describes mutation testing as stronger than line coverage because it changes code and checks whether tests fail. Its mutator documentation shows that mutation testing detects places where tests execute code but do not assert enough behavior. RegressionGuard should not attempt full mutation testing in v1, but assertion weakening and tautology detection are cheap diff-level approximations of the same concern.

Sources:

- PIT Mutation Testing - <https://pitest.org/>
- PIT Mutators - <https://pitest.org/quickstart/mutators/>

## Ideas to copy

- Use required status checks as the hard CI integration point.
- Separate project/package coverage floors from patch or regression coverage gates.
- Make every rule produce explicit pass, warn, or fail evidence.
- Treat new-code/diff evidence as first-class.
- Require intentional baseline changes to be reviewable in the diff and explicitly approved.
- Support repository-specific policy, but ship useful built-in rules.

## Ideas to avoid

- Do not become a general static analyzer. Semgrep, Sonar, SwiftLint, CodeQL, and similar tools already cover that lane.
- Do not rely only on total coverage percentage. Coverage can stay high while assertion strength falls.
- Do not treat AI review comments as the enforcement mechanism. Merge-blocking needs deterministic checks.
- Do not infer broad intent like "the agent got lazy" without a concrete diff signal.

## Gaps RegressionGuard should own

- Same-change suppression: a pull request can weaken the very tests, CI jobs, or config that would normally catch it.
- Assertion-strength regression: existing coverage gates do not tell whether assertions disappeared or became tautological.
- Review escape detection: changes to ignored/generated paths and exclusion lists can hide meaningful code from tools.
- Behavior deletion heuristics: not a hard correctness proof, but valuable warning evidence when control flow, validation, or error handling disappears.
- Agent-oriented remediation: findings should say what shortcut shape was detected and what evidence the agent must restore.

## Decision impact

This research supports keeping RegressionGuard narrow and evidence-driven. It should integrate with established CI checks rather than replace them, and its v1 rules should focus on shortcut-regression shapes that existing tools either do not detect or only detect indirectly.
