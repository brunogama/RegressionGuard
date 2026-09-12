Title: Agent remediation prompt
Labels: wayfinder:grilling
Status: closed
Assignee: pi
Parent: RegressionGuard agent laziness guardrail map
Blocked by: 06-ci-integration-and-observation-workflow, 08-v1-rule-catalog-and-detection-shapes, 10-output-and-observer-surface

## Question

Should RegressionGuard expose an agent-facing remediation prompt format in v1?

Resolve whether the stable CI report should include remediation instructions, whether a separate command or file should render prompts, and how to keep remediation bounded by observed evidence rather than allowing the guard to invent fixes or weaken tests.

## Resolution

V1 findings may include short, deterministic remediation hints in the stable report and presentation channels. A hint must be derived only from the observed rule evidence and must name a repair direction, not invent domain behavior or prescribe a patch.

Remediation hints must never recommend deleting, disabling, skipping, weakening, or commenting out tests, lowering coverage or lint thresholds, broadening ignored paths, or hiding the finding. The separate Swift observer may group these hints into a repair-oriented summary, but the core rule remains the source of truth.
