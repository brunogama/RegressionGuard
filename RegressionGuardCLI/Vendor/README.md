# Vendor

Every dependency `Package.local.swift` names, committed into this repository so an offline build
needs no network at all - not even a one-time clone before going offline.

Each is a **bare** git repository: directories of git objects, not a working tree, and not a
submodule. That shape is deliberate, and it is what separates this from vendoring source. A
`.package(path:)` gets no `Package.resolved` entry and no version, so the directory would be its
own pin. Referenced as local source control instead, SwiftPM reads the tags and **enforces the
declared version**, recording it like any other dependency.

Proven rather than assumed: with an empty SwiftPM cache, a prepared copy builds and runs all 248
tests, and the only repositories fetched are these two local paths.

## `swift-syntax.git`

```swift
.package(url: "Vendor/swift-syntax.git", "603.0.0"..<"604.0.0")
```

A copy on the wrong alignment series fails to resolve instead of quietly building a grammar the
rules were not written against.

| | |
|---|---|
| upstream | <https://github.com/swiftlang/swift-syntax> |
| tag | `603.0.2` |
| revision | `79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1` |
| contents | unmodified; shallow clone of that tag |
| licence | Apache 2.0 with Runtime Library Exception, copied to `swift-syntax-LICENSE.txt` |

## `Commander.git`

```swift
.package(url: "Vendor/Commander.git", from: "0.2.4")
```

Pre-1.0, so `from:` admits 0.2.x only - a 0.3 would be a breaking release and a decision rather
than a resolver outcome.

| | |
|---|---|
| upstream | <https://github.com/steipete/Commander> |
| tag | `v0.2.4` |
| revision | `bd219c4ee9032fee3e009856f81fcc6ec09a85f4` |
| contents | unmodified; shallow clone of that tag |
| licence | MIT, copied to `Commander-LICENSE.txt` |

## Both are referenced only from `Package.local.swift`

Never from `Package.swift`, and this is not a style preference. A vendored copy named in the
published manifest takes that package's identity in every consumer's dependency graph. Measured
with swift-syntax: a consumer that also depends on it then gets *this* copy instead of the one it
declared - its own dependency is never fetched, it gets no `Package.resolved` entry, and SwiftPM
reports only a warning that it "will be escalated to an error in future versions".

Silently substituting a dependency somebody pinned is precisely the class of failure this project
exists to catch. Consumers read only `Package.swift`, which keeps the upstream URLs, so these
unreferenced directories cost them a slightly larger clone and nothing else.

## The text hooks must not touch these

`prek.toml` excludes `Vendor/` from `trailing-whitespace`, `end-of-file-fixer`, and
`mixed-line-ending`. This is not tidiness: git writes `packed-refs` with a trailing space on its
header line, and the whitespace hook stripped it - a style rule editing another tool's storage. The
bytes here are upstream's, and this repository stores them rather than authoring them.

## Updating a pin

1. For swift-syntax, raise `SyntaxGrammar.pinnedAlignmentSeries` and move both bounds of the range
   in `Package.swift` and `Package.local.swift`. For Commander, move the version in both.
2. Re-clone the bare repository at the new tag, for example:
   `git clone --bare --depth 1 --branch <tag> <upstream> Vendor/<name>.git`
3. Update the table above: tag, revision, and licence file if upstream changed it.
4. Run `scripts/prepare-offline-validation.py`. It fails when the declared swift-syntax range and
   `pinnedAlignmentSeries` disagree - the one drift the resolver cannot see.
