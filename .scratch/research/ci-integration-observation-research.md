# CI integration and observation research

## Scope

---

This note supports the Wayfinder ticket `06-ci-integration-and-observation-workflow`. It combines first-party source research with direct inspection of the current Swift package and GitHub workflows.

## Repository evidence

---

- `Sources/regression-guard/RegressionGuardCommand.swift` currently exposes `check` and `coverage` commands, `text`, `json`, and `github` formats, and `--fail-on` severity handling.
- The check command throws `ExitCode.failure` when a violation meets the configured threshold. Coverage throws failure when any coverage violation exists.
- `JSONFormatter` currently emits a bare JSON array of `Violation` values. It has no schema version, run metadata, evidence references, or approval state.
- `GitHubAnnotationFormatter` emits workflow-command annotations only.
- `.github/workflows/regression-guard-self-check.yml` runs the tool with `--format github --fail-on error`, but does not write a job summary or upload a diagnostic artifact.
- `.github/actions/regression-guard/action.yml` builds the tool and runs the same GitHub annotation format. It has no report output contract or observer integration.

## First-party findings

---

1. GitHub workflow annotations are presentation commands and do not define the process exit status. The CLI must return a nonzero status for a blocking result. Source: [GitHub workflow commands](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions), section `Setting an error message`.
2. GitHub supports file, line, title, and message fields for `::error` and related workflow commands. Source: [Setting an error message](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message).
3. GitHub job summaries are written through `$GITHUB_STEP_SUMMARY` and are appropriate for human-readable counts, status, and links. Source: [Adding a job summary](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary).
4. `$GITHUB_OUTPUT` is intended for step outputs, while artifacts persist larger files for later inspection. Sources: [Setting an output parameter](https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-output-parameter) and [Store and share data with workflow artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data).
5. GitHub CLI exposes failed workflow logs and structured run fields through `gh run view`, including `--log-failed`, `--json`, and `--exit-status`. Source: [gh run view manual](https://cli.github.com/manual/gh_run_view).
6. Pull request checks and review activity are separate observation surfaces. Sources: [gh pr checks](https://cli.github.com/manual/gh_pr_checks), [gh pr view](https://cli.github.com/manual/gh_pr_view), and [pull_request_review webhook events](https://docs.github.com/en/webhooks/webhook-events-and-payloads#pull_request_review).

## Recommended CI contract

---

- `stdout`: one deterministic, versioned JSON report.
- `stderr`: human-readable diagnostics.
- Exit `0`: clean or advisory-only findings.
- Exit `1`: one or more blocking findings.
- Exit `2`: invocation, configuration, repository, or internal operational failure.
- GitHub presentation: annotations for actionable findings plus a concise `$GITHUB_STEP_SUMMARY`.
- Durability: upload the JSON report with `if: always()` so blocking failures retain their evidence.
- Observer inputs: workflow conclusion, failed job and step, failed logs, report artifact, PR checks, and newly observed review events.

The versioned report should contain the schema version, tool version, base and head refs, repository or commit identity, deterministic findings, severity, confidence, source location, message, evidence references, and approval state. Findings should be sorted by stable rule and location keys.

## Caveats

---

The delegated researcher could not directly retrieve source pages or read repository files, so its report marked source quotations and repository alignment as needing verification. The repository facts above were independently verified in the parent session. The DeepAPI synthesis returned a complete result and the first-party URLs above; exact wording should still be rechecked during implementation if an API behavior is uncertain.
