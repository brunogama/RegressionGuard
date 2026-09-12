# Vendor

Third-party source committed into this repository so an offline build needs no network.

## `swift-syntax.git`

A **bare** git repository - directories of git objects, not a working tree, and not a submodule.
That shape is deliberate. `Package.local.swift` references it as local source control:

```swift
.package(url: "Vendor/swift-syntax.git", "603.0.0"..<"604.0.0")
```

Because it is source control rather than a path dependency, SwiftPM reads its tags and **enforces
the range**. A vendored copy on the wrong alignment series fails to resolve instead of quietly
building a grammar the rules were not written against, and `Package.resolved` records a real
version and revision. A `.package(path:)` would get neither.

| | |
|---|---|
| upstream | <https://github.com/swiftlang/swift-syntax> |
| tag | `603.0.2` |
| revision | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` |
| contents | unmodified; shallow clone of that tag |
| licence | Apache 2.0 with Runtime Library Exception, copied to `swift-syntax-LICENSE.txt` |

### It is referenced only from `Package.local.swift`

Never from `Package.swift`, and this is not a style preference. A vendored copy named in the
published manifest takes the package identity `swift-syntax` in every consumer's dependency graph.
Measured: a consumer that also depends on swift-syntax then gets *this* copy instead of the one it
declared - its own dependency is never fetched, it gets no `Package.resolved` entry, and SwiftPM
reports only a warning that it "will be escalated to an error in future versions".

Silently substituting a dependency somebody pinned is precisely the class of failure this project
exists to catch. Consumers read only `Package.swift`, which keeps the upstream URL, so an
unreferenced directory costs them a slightly larger clone and nothing else.

### Updating the pin

1. Raise `SyntaxGrammar.pinnedAlignmentSeries`.
2. Move both bounds of the range in `Package.swift` and `Package.local.swift`.
3. Re-clone this repository at the new tag:
   `git clone --bare --depth 1 --branch <tag> https://github.com/swiftlang/swift-syntax.git Vendor/swift-syntax.git`
4. Run `scripts/prepare-offline-validation.py`, which fails when the range and the constant
   disagree - the one drift the resolver cannot see.
