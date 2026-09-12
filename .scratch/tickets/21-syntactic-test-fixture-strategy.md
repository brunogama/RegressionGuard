Title: Syntactic test fixture strategy
Labels: wayfinder:prototype
Status: open
Assignee: none
Parent: Swift-syntax syntactic evidence map
Blocked by: 16-syntactic-evidence-model

## Question

What should a rule test look like once rules consume parsed source?

`TestSupport.fileDiff(path:removed:added:)` hand-builds a diff from parallel string arrays today, synthesizing line numbers and never exercising a parser. Rules that read trees cannot be tested that way, and the fixtures are where the improved tests in this effort actually land.

Prototype a fixture pair and one migrated rule test to react to, then resolve: whether fixtures are real Swift files on disk at base and head or inline source strings parsed in the test; how a test expresses "this file changed this way" without hand-writing hunks; whether the existing line-based tests are kept to cover the degradation path; and what keeps fixtures readable as the rule catalog grows.
