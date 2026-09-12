import Testing
@testable import RegressionGuardKit

@Suite("Git diff parser tests")
struct GitDiffParserTests {
  @Test("parses a simple modified file")
  func parsesASimpleModifiedFile() {
    let raw = """
      diff --git a/Sources/Foo.swift b/Sources/Foo.swift
      index 1234567..89abcde 100644
      --- a/Sources/Foo.swift
      +++ b/Sources/Foo.swift
      @@ -1,3 +1,3 @@
       func foo() {
      -    return 1
      +    return 2
       }
      """

    let files = GitDiffParser().parse(raw)
    #expect(files.count == 1)
    let file = files[0]
    #expect(file.oldPath == "Sources/Foo.swift")
    #expect(file.newPath == "Sources/Foo.swift")
    #expect(!file.isDeleted)
    #expect(!file.isAdded)
    #expect(file.removedLines.map { $0.text } == ["    return 1"])
    #expect(file.addedLines.map { $0.text } == ["    return 2"])
  }

  @Test("parses a deleted file")
  func parsesADeletedFile() {
    let raw = """
      diff --git a/Tests/FooTests.swift b/Tests/FooTests.swift
      deleted file mode 100644
      index 1234567..0000000
      --- a/Tests/FooTests.swift
      +++ /dev/null
      @@ -1,3 +0,0 @@
      -func testFoo() {
      -    XCTAssertTrue(true)
      -}
      """

    let files = GitDiffParser().parse(raw)
    #expect(files.count == 1)
    #expect(files[0].isDeleted)
    #expect(files[0].oldPath == "Tests/FooTests.swift")
    #expect(files[0].newPath == nil)
  }

  @Test("parses multiple files in one diff")
  func parsesMultipleFilesInOneDiff() {
    let raw = """
      diff --git a/A.swift b/A.swift
      index 111..222 100644
      --- a/A.swift
      +++ b/A.swift
      @@ -1,1 +1,1 @@
      -let a = 1
      +let a = 2
      diff --git a/B.swift b/B.swift
      index 333..444 100644
      --- a/B.swift
      +++ b/B.swift
      @@ -1,1 +1,1 @@
      -let b = 1
      +let b = 2
      """

    let files = GitDiffParser().parse(raw)
    #expect(files.count == 2)
    #expect(files[0].newPath == "A.swift")
    #expect(files[1].newPath == "B.swift")
  }
}
