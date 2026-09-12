# Agent instructions

## Project

- Write swift code following Google Swift Guideline
- Do not edit formatting files and read `.swift-format`, `.swiftlint.yml`.
- Code must consider the formatting and linting budgets.

## Required startup

1. Read `CLAUDE.md` when the active harness loads it.
2. Read `CONTEXT.md`. It is the glossary; use its terms with exactly the
   meanings recorded there.
3. Read the ticket you are implementing, under `.scratch/tickets/`. It is the
   authoritative contract for that work.
4. Read its parent map ticket and the resolutions of the closed tickets the map
   lists. They are settled decisions - implement them rather than relitigating
   them.

## Implementation

- Swift 6.4, tools version 6.0, macOS 14 minimum, complete concurrency
  checking.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`), not
  XCTest. See `rules/testing.md`.
- Targets are declared in `Package.swift` as their source directories land. A
  target whose directory does not exist yet cannot be declared, so add the
  declaration in the ticket that creates the sources.
- Do not add dependencies that the ticket you are implementing does not call
  for.

## Work tracking

Implementation work is tracked as local Markdown tickets under
`.scratch/tickets/`. A ticket carries `Title`, `Labels`, `Status`, `Assignee`,
`Parent`, and `Blocked by` as leading key-value lines, then a `## Question`
section; a `wayfinder:grilling` ticket is closed by appending a `## Resolution`
section and adding a line to its parent map's "Decisions so far".
Tickets carry their own blocking edges; `scripts/local-ticket-loop/` executes
them and owns their checkboxes. Do not edit a ticket's checkboxes by hand while
a loop is running.

## Skill lifecycle

No skill becomes permanent without:

    Collect -> Induction -> Deduction -> De-dup -> Approval

Never write a new skill directly to an active skill directory. Stage it under
the harness-specific `_candidates/<skill-name>/` directory and wait for
explicit human approval.

## Quality

- Run `swift build --build-tests && swift test` before completion.
- Run `uv run scripts/qa_repository.py .` for agent-infrastructure changes. It
  checks the repository's own tracked files, so build output and vendored
  checkouts are not its subject. Then ask a fresh agent to review the change.
- Never enable or execute an external skill source before reviewing it.
- Do not place credentials, tokens, or private URLs in generated prompts or
  workflows.

## Version control

This repository uses Git as its only VCS and follows Gitflow: `main` for released
history, plus `feature/*`, `release/*`, and `hotfix/*` branches. There is no
Jujutsu metadata and Jujutsu commands must not be used for repository operations.
Branches under `local-ticket-loop/*` are created and owned by the ticket loop; leave
them alone.
- A merge to `main` updates `CHANGELOG.md` in Keep a Changelog format.
- A version-tag push updates README sample-code version references in the same release
  change.
- CI workflows run independently in parallel. Any failure cancels the other in-progress
  workflows for the same pull request.

## Rules modules

| File | Topic |
|------|-------|
| `rules/general.md` | General working agreements |
| `rules/rule-loading.md` | Dynamic rule-loading protocol |
| `rules/commits.md` | Commit message conventions |
| `rules/testing.md` | Testing standards and commands |
| `rules/mcp-tools-usage.md` | MCP tool usage policy |
| `rules/self_improve.md` | Agent self-improvement loop |

`rules/view.md` and `rules/view-model.md` cover SwiftUI conventions. This
package has no UI layer, so they do not apply to work here.

## Conventions

- Keep each module focused on one topic; split when a file exceeds ~200 lines.
- Exception: `scripts/local-ticket-loop/*.sh` may exceed this line-count guideline when the entrypoint must remain a portable, self-contained Bash 3.2 harness. Keep shared logic in `scripts/local-ticket-loop/shared/` when it is used by multiple entrypoints.
- Prefer executable commands over prose descriptions.
- Establish positive defaults ("always add tests") rather than bans.
- Treat stale rules as technical debt; update modules when conventions change.

---

## Source organization

- Organize every Swift target as `Sources/<Feature>/<Domain>/<Type>.swift`.
- Put exactly one Swift type or extension in each Swift file; name the file after that declaration.
- Treat `.swiftlint.yml` as the authoritative listing budget. Before reaching it, extract a collaborating type or a domain-specific extension into its own file.
- Implement macro expansions with SwiftSyntax AST builders, never raw generated-source strings.
