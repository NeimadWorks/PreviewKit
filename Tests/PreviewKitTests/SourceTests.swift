// Tests for `SourceLanguage`, `SourceTokenizer`, and `SourceOutline`.
// All three are pure Swift logic — no SwiftUI, no async, fast to
// exercise against small fixture strings.

import XCTest
@testable import PreviewKit

final class SourceTests: XCTestCase {

    // MARK: - Regression: bare sigils must not hang the scanner

    /// `<h1>#</h1>`, `mailto:x@` in text nodes, bare `@` / `#` glyphs —
    /// the tokenizer used to spin forever on these because the identifier
    /// branch's inner while loop rejected the sigil itself and `index`
    /// never advanced. This test fails by timing out if the bug returns.
    func testBareSigilDoesNotHang() {
        let samples = [
            "<h1>#</h1>",
            "<p>Question # 1</p>",
            "<a href=\"mailto:foo@\">@</a>",
            "#",
            "@",
            "# @ # @",
            "<html><body>@#@#@ mixed with text</body></html>",
        ]
        for src in samples {
            // Each must complete and produce at least one token.
            let tokens = SourceTokenizer.tokens(in: src, language: .html)
            XCTAssertFalse(tokens.isEmpty, "empty tokens for \(src.debugDescription)")
        }
    }

    func testSigilFollowedByWordIsIdentifier() {
        // Sanity: `@media` still tokenizes as a single identifier+word run.
        let tokens = SourceTokenizer.tokens(in: "@media", language: .css)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.text, "@media")
    }

    // MARK: - SourceLanguage

    func testLanguageInitFromArtifactKind() {
        XCTAssertEqual(SourceLanguage(kind: .sourceSwift), .swift)
        XCTAssertEqual(SourceLanguage(kind: .sourceJS),    .javascript)
        XCTAssertEqual(SourceLanguage(kind: .sourceTS),    .typescript)
        XCTAssertEqual(SourceLanguage(kind: .sourcePython), .python)
        XCTAssertEqual(SourceLanguage(kind: .sourceShell), .shell)
        XCTAssertEqual(SourceLanguage(kind: .pdf),         .unknown)
    }

    func testKeywordSetsContainCanonicalMembers() {
        XCTAssertTrue(SourceLanguage.swift.keywords.contains("func"))
        XCTAssertTrue(SourceLanguage.swift.keywords.contains("struct"))
        XCTAssertTrue(SourceLanguage.python.keywords.contains("def"))
        XCTAssertTrue(SourceLanguage.rust.keywords.contains("fn"))
        XCTAssertTrue(SourceLanguage.go.keywords.contains("func"))
    }

    func testCommentDelimitersPerLanguage() {
        XCTAssertEqual(SourceLanguage.swift.singleLineComment, "//")
        XCTAssertEqual(SourceLanguage.python.singleLineComment, "#")
        XCTAssertEqual(SourceLanguage.shell.singleLineComment, "#")
        XCTAssertNil(SourceLanguage.html.singleLineComment)
        XCTAssertEqual(SourceLanguage.html.multiLineComment?.open, "<!--")
    }

    // MARK: - SourceTokenizer

    func testTokenizerClassifiesSwiftKeywordsAndStrings() {
        let src = #"func hello() { let greeting = "world" }"#
        let tokens = SourceTokenizer.tokens(in: src, language: .swift)
        let keywords = tokens.filter { $0.kind == .keyword }.map(\.text)
        let strings = tokens.filter { $0.kind == .string }.map(\.text)
        XCTAssertTrue(keywords.contains("func"))
        XCTAssertTrue(keywords.contains("let"))
        XCTAssertEqual(strings.first, "\"world\"")
    }

    func testTokenizerRecognisesLineComments() {
        let src = "// leading comment\nlet x = 1"
        let tokens = SourceTokenizer.tokens(in: src, language: .swift)
        let comment = tokens.first(where: { $0.kind == .comment })
        XCTAssertEqual(comment?.text, "// leading comment")
    }

    func testTokenizerRecognisesBlockComments() {
        let src = "/* multi\nline */ let x = 1"
        let tokens = SourceTokenizer.tokens(in: src, language: .swift)
        let comment = tokens.first(where: { $0.kind == .comment })
        XCTAssertEqual(comment?.text, "/* multi\nline */")
    }

    func testTokenizerRecognisesNumbers() {
        let src = "let pi = 3.14159\nlet n = 0xFF"
        let tokens = SourceTokenizer.tokens(in: src, language: .swift)
        let numbers = tokens.filter { $0.kind == .number }.map(\.text)
        XCTAssertTrue(numbers.contains("3.14159"))
        XCTAssertTrue(numbers.contains("0xFF"))
    }

    func testTokenizerClassifiesTypeNames() {
        let src = "let arr: Array<String> = []"
        let tokens = SourceTokenizer.tokens(in: src, language: .swift)
        let types = tokens.filter { $0.kind == .type }.map(\.text)
        XCTAssertTrue(types.contains("Array"))
        XCTAssertTrue(types.contains("String"))
    }

    func testColorizeProducesNonEmptyAttributedString() {
        let src = "let x = 1"
        let out = SourceTokenizer.colorize(src, language: .swift)
        XCTAssertEqual(String(out.characters), src)
    }

    // MARK: - SourceOutline summary

    func testSwiftSummaryCountsFunctionsAndTypes() {
        let src = """
        import Foundation
        struct Widget {
            func compute() -> Int { 0 }
            func render() {}
        }
        class Helper {}
        enum Mode { case on, off }
        // TODO: finish this
        """
        let sum = SourceOutline.summarise(source: src, language: .swift)
        XCTAssertGreaterThan(sum.lineCount, 5)
        XCTAssertEqual(sum.functionCount, 2)
        XCTAssertEqual(sum.typeCount, 3)   // struct, class, enum
        XCTAssertEqual(sum.todoCount, 1)
        XCTAssertEqual(sum.importNames, ["Foundation"])
    }

    func testPythonImportExtraction() {
        let src = """
        from pathlib import Path
        import os
        import sys
        """
        let sum = SourceOutline.summarise(source: src, language: .python)
        XCTAssertGreaterThan(sum.importCount, 0)
    }

    func testSwiftOutlineProducesEntries() {
        let src = """
        public struct Foo {
            func run() {}
        }
        public enum Kind {}
        """
        let outline = SourceOutline.extractOutline(source: src, language: .swift)
        XCTAssertFalse(outline.isEmpty)
        let titles = outline.map(\.title)
        XCTAssertTrue(titles.contains("Foo"))
        XCTAssertTrue(titles.contains("Kind"))
        XCTAssertTrue(titles.contains("run"))
    }

    func testRustOutlineCapturesStructsAndFunctions() {
        let src = """
        pub struct Config {}
        pub fn main() {}
        """
        let outline = SourceOutline.extractOutline(source: src, language: .rust)
        XCTAssertFalse(outline.isEmpty)
    }

    func testSwiftAsyncAndMainActorDetection() {
        let src = """
        @MainActor
        func go() async throws {}
        """
        let sum = SourceOutline.summarise(source: src, language: .swift)
        XCTAssertTrue(sum.hasAsync)
        XCTAssertTrue(sum.hasMainActor)
    }
}
