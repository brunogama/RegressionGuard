# CI Observer Design Research

- **Method:** Exa Search (`type: deep`) with official GitHub documentation and GitHub CLI documentation restricted by domain.
- **Date:** 2026-09-12
- **Request IDs:** `bb9a2fc474c97b71968072b3b37beca2`, `9c67c61c368c04426aa3cf80d3ca771f`, `6d0c3b2b71de58cdd7c50f9685739246`, `3dbdcaac086243de78064c9b2f2bfebe`

## Findings

1. **Workflow commands are the correct presentation channel for inline annotations.** GitHub's workflow-command reference says commands use `::` syntax and are sent to the runner over stdout. It documents `error`, `warning`, and `notice`, and maps `core.error` to `error`. Source: [Workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands).

2. **Job summaries should be written through `GITHUB_STEP_SUMMARY`.** The same GitHub reference maps `core.summary` to the `GITHUB_STEP_SUMMARY` environment file. This is appropriate for a compact human-readable report while JSON remains the machine contract. Source: [Workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands).

3. **A failure diagnostic artifact should be uploaded even when the policy command fails.** GitHub's workflow syntax documents that jobs depending on a failed job are skipped unless a conditional expression allows continuation. Therefore, artifact publication belongs in a same-job step guarded with `if: ${{ always() }}`, or in a job with an explicit continuation condition. Source: [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

4. **Artifact retention is bounded and configurable.** GitHub documents a default 90-day retention period for workflow artifacts and logs, with public repositories configurable from 1 to 90 days and private repositories from 1 to 400 days. The observer should therefore retain only the versioned report and raw failure evidence needed for repair, with an explicit retention input rather than assuming indefinite storage. Source: [Repository Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-your-repository).

5. **Failed-run diagnosis needs both step status and downloadable logs.** GitHub says failed workflow runs expose the step that failed, searchable logs, and downloadable logs and artifacts. The observer should capture run status, failed job and step names, log URLs or downloaded log paths, and artifact names rather than scraping only console text. Source: [Using workflow run logs](https://docs.github.com/en/actions/how-tos/monitor-workflows/use-workflow-run-logs).

6. **`gh pr checks --json` is a useful normalized PR status input.** The GitHub CLI reference says JSON output includes a `bucket` field categorizing checks as `pass`, `fail`, `pending`, `skipping`, or `cancel`. This is a better observer input than parsing the default table output. Source: [gh pr checks](https://cli.github.com/manual/gh_pr_checks).

7. **`gh run view --json` supplies run and job metadata, but log association is imperfect.** The CLI documentation warns that job-to-log association may fail when fetching the primary log ZIP, then falls back to individual job API requests; missing more than 25 job logs can fail the operation. The observer must tolerate absent step associations and retain the run URL and job-level fallback errors as evidence. Source: [gh run view](https://cli.github.com/manual/gh_run_view).

8. **Workflow history has stable run fields useful for correlation.** `gh run list --json` documents fields including `attempt`, `conclusion`, `headSha`, `status`, `updatedAt`, `url`, and workflow identity. The observer should correlate report evidence by commit SHA, workflow, run ID, and attempt, not by display title alone. Source: [gh run list](https://cli.github.com/manual/gh_run_list).

9. **Review outcomes and diff comments are separate GitHub concepts.** GitHub's REST documentation describes pull request reviews as grouped review comments with a review state and optional body, while review comments are comments on a portion of the unified diff and differ from issue or commit comments. Calibration should therefore store review ID, state, body or classification, and diff-comment references separately. Sources: [Pull request reviews](https://docs.github.com/en/rest/pulls/reviews) and [Pull request review comments](https://docs.github.com/en/rest/pulls/comments).

10. **Check runs are richer than binary commit statuses.** GitHub documents that check runs can report detailed feedback and annotations, while check suites group runs for a commit. The local observer does not need to create a check run, but its evidence model should preserve check name, conclusion, annotations, and commit association where available. Source: [Check runs](https://docs.github.com/en/rest/checks/runs) and [Checks API guide](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-checks).

## Repository alignment

- `.github/workflows/ci.yml` currently runs `swift build --build-tests` and `swift test --parallel` on `macos-14`.
- `.github/workflows/regression-guard-self-check.yml` invokes the CLI with `--format github --fail-on error` against the pull request base and head SHA.
- `.github/actions/regression-guard/action.yml` is a composite action that checks out and builds the guard tool, then runs the CLI from the consuming repository.
- `Sources/regression-guard/RegressionGuardCommand.swift` currently emits text, JSON, or GitHub output and throws ArgumentParser's failure exit code for policy findings, but has no explicit operational exit code or report-file option.
- `Sources/RegressionGuardKit/RegressionGuardRunner.swift` currently returns only `[Violation]`; the planned `EvidenceBundle` and versioned report envelope should be introduced above or alongside this seam without losing the existing rule execution path.

## Recommendation

Use a versioned JSON report as the sole machine-readable contract. The CLI should always write it when a report path is supplied, including policy failures. GitHub presentation should be derived from the same findings and emit annotations plus a Markdown summary through `GITHUB_STEP_SUMMARY`. A same-job `always()` artifact step should upload the JSON report, raw command output, and any available observer metadata. A separate read-only Swift observer should consume those artifacts and normalized `gh` JSON, tolerate missing logs, and produce a deterministic repair summary keyed by stable evidence IDs.

Do not make the observer responsible for policy decisions, automatic reruns, comments, or severity changes. Keep those as explicit future actions requiring maintainer authorization. Review and calibration data should distinguish confirmed shortcut, legitimate change, and inconclusive outcomes; unreviewed findings must not be counted as false positives.

## Open implementation risks

- GitHub log and review APIs require permissions that may not be available to every pull request workflow, especially forked pull requests. The observer must degrade to URLs and available metadata without failing the guard itself.
- Artifact publication must not hide the original policy exit code. Capture the command status, publish evidence, then re-emit the original status.
- Do not parse human-oriented CLI tables when a documented JSON field is available.
- The current SwiftPM test run reports three unhandled snapshot-resource warnings. Resolve this in CI wiring without modifying generated snapshot files.

## Confidence

High for GitHub workflow commands, summaries, artifact retention, run logs, and CLI JSON fields because the sources are official documentation. Medium for the final local observer shape because it is a repository design recommendation derived from those primitives rather than a GitHub requirement.
