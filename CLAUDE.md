# Claude project instructions

Follow `AGENTS.md` as the shared policy source.

## Permissions

- Read repository files freely.
- Write candidate skills under the active harness-specific `_candidates/` directory: `.claude/skills/_candidates/` for Claude or `.pi/skills/_candidates/` for Pi.
- Promote candidates only after explicit human approval.
- Never edit `learnings/SKILLS-LOG.md` for an unapproved candidate.

## Commands

- `/forge-skill` stages a candidate skill.
- `/qa` runs the repository QA procedure.
- `/peer-review` prepares a bounded peer review request.

---

## Agent skills

### Issue tracker

Issues are tracked as local Markdown under `.scratch/tickets/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the five canonical label names. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository with a lazily created root `CONTEXT.md` and system-wide ADRs under `docs/adr/`. See `docs/agents/domain.md`.
