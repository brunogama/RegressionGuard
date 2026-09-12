Title: Offline vendoring of swift-syntax
Labels: wayfinder:task
Status: open
Assignee: none
Parent: Swift-syntax syntactic evidence map
Blocked by: none

## Question

How does `Package.local.swift` resolve swift-syntax without network access?

Arises from the dependency posture decision, which treated offline build support as live. That manifest uses path dependencies (`../swift-argument-parser`) and is backed by `scripts/prepare-offline-validation.py`. swift-syntax is a much larger checkout than swift-argument-parser, and the syntax target needs it present for an offline build to produce a syntax-aware binary.

Do the work of vendoring it and record what the offline path now requires: where the checkout lives, which revision is pinned and how that pin stays aligned with the version range in `Package.swift`, what `prepare-offline-validation.py` must do differently, and how much disk and build time the offline route now costs. If offline builds turn out to be unable to carry syntactic evidence, say so plainly here, since the parity decision then requires telling those consumers rather than silently degrading them.
