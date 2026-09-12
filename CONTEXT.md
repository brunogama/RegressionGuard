# RegressionGuard

RegressionGuard protects software changes from shortcut regressions: changes that make a failing or incomplete implementation appear healthy by weakening the evidence used to judge it.

## Language

**Shortcut regression**:
A change that removes, weakens, hides, or bypasses evidence of required software behavior instead of addressing the underlying problem.
_Avoid_: Lazy code, bad code, agent mistake.

**Evidence signal**:
An observable change or measurement that supports or undermines confidence in the behavior of a software change.
_Avoid_: Vibe, suspicion.

**Evidence bundle**:
The single rule input that combines diff-local signals with optional repository-wide evidence. Missing optional evidence is explicit and may reduce confidence or make a result inconclusive; it is never an implicit pass.
_Avoid_: File-only evidence, hidden context.

**CI report**:
A deterministic, versioned machine-readable record of a guard run, preserving all findings and the evidence needed to audit or observe the result.
_Avoid_: Log scrape, annotation-only result.

**Coverage floor**:
An explicit minimum overall line-coverage percentage. RegressionGuard's own floor is 90%+; a guarded repository may configure a floor from 70% through 100%.
_Avoid_: Universal consumer default, coverage vibe.

**High-confidence finding**:
A shortcut regression supported by a concrete, low-ambiguity signal and suitable for blocking by default.
_Avoid_: Certain bug, proof of intent.

**Heuristic finding**:
A shortcut regression suggested by a pattern that can also occur in legitimate maintenance, requiring warning or review rather than automatic rejection.
_Avoid_: False positive, low-quality finding.

**Approval marker**:
An explicit, reviewable acknowledgement that an otherwise-protected change is intentional.
_Avoid_: Bypass, ignore flag.

**Baseline drift**:
A change to recorded expected behavior that requires reviewers to confirm the new behavior is intentional.
_Avoid_: Snapshot noise.

**Guarded repository**:
A repository that uses RegressionGuard as part of its change-validation policy.
_Avoid_: Client repository, target project.

**Blocking finding**:
A high-confidence finding that prevents a change from being accepted until it is fixed or explicitly handled by the repository policy.
_Avoid_: Fatal warning, hard opinion.

**Advisory finding**:
A heuristic finding that remains visible for review but does not prevent acceptance by default.
_Avoid_: Non-issue, harmless warning.

**Scoped approval**:
An approval marker that names the rule or change category it authorizes, preventing a broad acknowledgement from silently covering unrelated findings.
_Avoid_: Blanket approval, global bypass.
