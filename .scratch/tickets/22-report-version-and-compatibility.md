Title: Report version and compatibility
Labels: wayfinder:grilling
Status: closed
Assignee: claude
Parent: Swift-syntax syntactic evidence map
Blocked by: 18-text-rule-migration-contract, 19-ast-rule-catalog

## Question

What does a guarded repository experience when it upgrades to a syntax-aware RegressionGuard?

Two compatibility surfaces move at once: existing rule IDs get sharper and will report findings on code their repository never touched, and new advisory rule IDs appear that no existing configuration mentions.

Resolve the report envelope version and what changes inside it, how syntactic evidence is represented in the JSON report so a finding stays auditable, how the observer treats rule IDs it has no calibration history for, what a repository must do to adopt or defer the new families, and what the upgrade note must tell a maintainer whose build is about to turn red.

## Resolution

The envelope goes to `schemaVersion: 2`, and the bump carries everything two earlier tickets
deferred to it. Four fields arrive, and each exists for one reason: a weaker run must not be able
to read as a stronger one.

`findings[].evidence` carries `diff`, `syntax`, or `degradedDiff`, which the text rule migration
contract settled and deliberately left unserialised until this bump. A finding reached without the
tree its rule asked for is the weaker claim, and one that cannot say so is indistinguishable from
the sharper answer.

`syntacticEvidenceGaps` puts the run's evidence holes in the artifact rather than only on stderr.
That was the actual gap in the previous arrangement: the report a repository keeps, audits, and
feeds to the observer looked identical whether the run had parsed everything or nothing, and log
output does not survive. Stderr keeps its human-facing summary; the report keeps the per-file
record.

`syntaxGrammar` carries the alignment series that judged the run, deferred here by the version pin
decision, and is absent rather than a placeholder when no parser was available.

`rules` lists every rule that ran and whether it could have failed the build. This one was not on
the ticket and turned out to be the load-bearing piece of the compatibility story: a family that
ran and found nothing leaves no findings behind, so without this, "no `implementation_stubbed`
findings" is ambiguous between a clean result and a guard version that never had the rule.
`blocking` is derived from the run's own `--fail-on` threshold rather than restated, so the report
cannot claim a family is advisory while the run was configured to fail on it.

`approvalSuppressed` is the fifth, and arrived from review rather than from the question. An
approved run returns early with no findings and no rules, which under the new semantics is
byte-shaped like a guard version that has no rules at all - reintroducing the very ambiguity
`rules` was added to close. The report now says which it was.

Version 1 consumers keep working for every field they already read. All five additions are new
keys; nothing was renamed or removed.

**Compatibility runs in both directions, and the second one was nearly missed.** A report is an
artifact a repository stores and hands back later, and this project's own observer loads reports
off disk to calibrate rules. Synthesised `Codable` made the added fields required on decode, so a
stored version 1 report threw `keyNotFound` and the calibration path - the same path advisory
promotion depends on - would have broken on the first upgrade. `GuardFinding` and `GuardReport`
therefore decode the additions with `decodeIfPresent`: an absent `evidence` reads as `.diff`,
which is the only claim a version 1 finding ever made, and absent collections read as empty.
`schemaVersion` is decoded from the document rather than restamped, so a report still says which
version wrote it. The regression test decodes a literal version 1 document, because a round trip
through the current type cannot catch this class of break at all.

### The observer and rules it has never seen reviewed

Two changes, both about absence.

`RuleCalibration.hasReviewHistory` separates "nobody has looked at this family yet" from "there is
nothing to compute a rate from". `falsePositiveRate == nil` already existed and conflated them,
which is tolerable while every rule is old and intolerable the moment three arrive with no review
history at all. A maintainer promoting a rule to blocking needs the difference, and absence of
evidence must never be presented as evidence of accuracy.

The observer now builds a calibration for every rule the report says ran, not only the ones that
produced findings. Grouping findings by rule ID - the previous behaviour - drops a silent family
from the artifact entirely, and an absent rule reads like a rule that was never there. This is the
same failure shape as an unrequested file reading as a clean one, and it is closed the same way:
by recording what was asked, not only what answered.

### Adoption and deferral

Nothing is required. The three new families are advisory by construction - they report at
`warning`, and the default `--fail-on error` does not block on it - so an upgrade that changes no
configuration cannot turn a build red on their account.

To adopt one, raise its severity to `error`. To defer one, set `enabled: false`. Both are ordinary
`.regressionguard.yml` entries needing no new syntax, and `regression-guard init` now writes the
three with a comment saying exactly that, so a repository generating a fresh config sees the
choice rather than discovering the rules later.

### What the upgrade note says

Written into `README.md` as its own section rather than a changelog line, because the question a
maintainer arrives with is "why is this red now", and that needs to be answerable from the docs
the repository already reads.

It says the plain thing first, and says it per threshold rather than flatly. On the default
`--fail-on error`, a red build is an existing blocking rule reporting something the line matcher
used to miss, because the new families report at `warning`. On `--fail-on warning`, which some
repositories already run, the three new families *can* turn a build red with no configuration
change, because `warning` is exactly where they report. An earlier draft of this note claimed
they never could; that conflated the rule default with the threshold default. It names the common
sharpened cases - a tautology spread over two lines, a whole
`@Suite(.disabled)`, a `return` the old matcher counted inside a string literal - so a maintainer
can recognise their own finding. It directs them to read `evidence` first, since `degradedDiff`
means the sharper check never ran and the finding stands at text precision. And it gives the two
escape hatches, adopt and defer, as configuration rather than advice.

### Consequences accepted

A run with no parser records two gap entries per changed Swift file, which is verbose and says the
same thing every time. Collapsing it would lose which files were affected, and that is the
auditable part; stderr already carries the one-line summary for a human. Verbosity in a
machine-readable artifact is the cheaper mistake.

`schemaVersion` is an integer with no negotiation mechanism. A consumer pinned to 1 that validates
the version strictly will reject a version 2 report rather than ignore the new keys. That is the
existing contract's behaviour and this ticket does not change it; if strict consumers turn out to
exist, that is a separate decision about tolerance, not about this bump.

A deferred rule - one a repository set `enabled: false` - was originally absent from `rules`,
which reproduced "absent reads as never present" for exactly the path the upgrade note
recommends. That is now closed rather than tolerated: `ReportedRule` carries `enabled`, deferred
rules are listed with it `false`, and a rule that did not run reports `blocking: false` whatever
its configured severity says, because a rule that never ran cannot have failed the build.
