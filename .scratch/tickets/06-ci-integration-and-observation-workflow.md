Title: CI integration and observation workflow
Labels: wayfinder:research
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 02-existing-guardrails-research, 03-enforcement-policy-and-severity-model

## Question

How should RegressionGuard run in CI and surface findings so agents and humans can fix them quickly?

Resolve the CI contract: command shape, GitHub Actions annotations, JSON output, failure codes, artifact needs, and whether the package should emit enough structured data for an observing script to repair failures after CI or review comments arrive. This is AFK research plus design synthesis.

## Resolution

Keep the existing `check` and `coverage` commands and the `--base`, `--head`, `--format`, and `--fail-on` options. Add a stable versioned JSON report envelope and a report-file output path for CI. The report file is the machine contract; text and GitHub formats remain presentation channels for local use and annotations.

CI should run the guard once with the GitHub presentation format plus the JSON report file, write a concise Markdown summary to `$GITHUB_STEP_SUMMARY`, and upload the report with `if: always()`. Annotations must identify the rule, severity, file, line when available, and actionable message. The report must preserve all findings, including advisory and approved findings, rather than only the failures shown inline.

Use exit status 0 for clean or advisory-only results, 1 for blocking findings at or above `--fail-on`, and 2 for configuration, repository, invocation, or internal errors. The implementation must keep operational errors distinct from a policy failure even when the host is GitHub Actions.

The report envelope includes `schemaVersion`, tool version, base and head refs, repository identity, deterministic findings, severity, confidence, source location, evidence references, and approval state. Sort findings by stable rule and location keys. An observing script consumes the workflow conclusion, failed job and step, failed logs, report artifact, PR checks, and newly observed review activity; CI observations and review observations remain separate input streams. Research findings are recorded in `.scratch/research/ci-integration-observation-research.md`.
