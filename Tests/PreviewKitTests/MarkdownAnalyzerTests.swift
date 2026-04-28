// Tests for MarkdownAnalyzer — heading extraction, frontmatter
// stripping, wikilink detection, lead-paragraph heuristic, word count,
// and the high-level `summarise` tally.

import XCTest
@testable import PreviewKit

final class MarkdownAnalyzerTests: XCTestCase {

    // MARK: - Frontmatter

    func testStripFrontmatterYAML() {
        let source = """
        ---
        title: Hello
        tags: [a, b]
        ---
        # Heading
        Body text here.
        """
        let (body, had) = MarkdownAnalyzer.stripFrontmatter(source)
        XCTAssertTrue(had)
        XCTAssertTrue(body.contains("# Heading"))
        XCTAssertFalse(body.contains("title:"))
    }

    func testStripFrontmatterNoneReturnsOriginal() {
        let source = "# Heading\nBody"
        let (body, had) = MarkdownAnalyzer.stripFrontmatter(source)
        XCTAssertFalse(had)
        XCTAssertEqual(body, source)
    }

    // MARK: - Headings

    func testExtractHeadingsUpToH3() {
        let source = """
        # H1 Title
        ## H2 Subsection
        ### H3 Detail
        #### H4 Too deep
        """
        let headings = MarkdownAnalyzer.extractHeadings(from: source)
        XCTAssertEqual(headings.count, 3)
        XCTAssertEqual(headings.map(\.title), ["H1 Title", "H2 Subsection", "H3 Detail"])
        XCTAssertEqual(headings.map(\.depth), [0, 1, 2])
        XCTAssertEqual(headings.map(\.kind), [.heading, .heading, .heading])
    }

    func testHeadingWeightFractionSumsAtMostOne() {
        let source = """
        # One
        body
        # Two
        body body body body
        # Three
        """
        let headings = MarkdownAnalyzer.extractHeadings(from: source)
        let sum = headings.map(\.weightFraction).reduce(0, +)
        XCTAssertLessThanOrEqual(sum, 1.001)
        XCTAssertGreaterThan(sum, 0)
    }

    func testHeadingEmptyInputYieldsEmptyArray() {
        XCTAssertTrue(MarkdownAnalyzer.extractHeadings(from: "").isEmpty)
        XCTAssertTrue(MarkdownAnalyzer.extractHeadings(from: "just prose").isEmpty)
    }

    // MARK: - Wikilinks

    func testExtractPlainWikilink() {
        let relations = MarkdownAnalyzer.extractWikilinks(from: "See [[Other Note]] here.")
        XCTAssertEqual(relations.count, 1)
        XCTAssertEqual(relations[0].type, .wikiLinksTo)
        XCTAssertEqual(relations[0].targetDisplayName, "Other Note")
    }

    func testExtractAliasedWikilink() {
        let relations = MarkdownAnalyzer.extractWikilinks(from: "See [[Real Target|Display Alias]].")
        XCTAssertEqual(relations.count, 1)
        XCTAssertEqual(relations[0].targetDisplayName, "Display Alias")
    }

    func testExtractMultipleWikilinks() {
        let source = "Link to [[One]] and [[Two|Alias]] and [[Three]]."
        let relations = MarkdownAnalyzer.extractWikilinks(from: source)
        XCTAssertEqual(relations.count, 3)
        XCTAssertEqual(relations.map(\.targetDisplayName), ["One", "Alias", "Three"])
    }

    // MARK: - Lead paragraph

    func testFirstParagraphSkipsHeadings() {
        let source = """
        # Title
        First prose line here.
        Still the same paragraph.

        Second paragraph shouldn't be included.
        """
        let lead = MarkdownAnalyzer.firstParagraph(in: source)
        XCTAssertNotNil(lead)
        XCTAssertTrue(lead!.contains("First prose line"))
        XCTAssertFalse(lead!.contains("Second paragraph"))
    }

    func testFirstParagraphReturnsNilForEmptyOrHeadingOnly() {
        XCTAssertNil(MarkdownAnalyzer.firstParagraph(in: ""))
        XCTAssertNil(MarkdownAnalyzer.firstParagraph(in: "# Only heading"))
    }

    // MARK: - Summarise

    func testSummariseProducesCoherentStats() {
        let source = """
        ---
        title: Doc
        ---
        # Chapter 1
        Lorem ipsum dolor sit amet, consectetur.
        - [ ] task one
        - [x] task two
        [A link](https://x.com) and [[Wiki Note]].
        Some $x = 1$ inline math.

        ## Section
        """
        let stats = MarkdownAnalyzer.summarise(source: source)
        XCTAssertTrue(stats.hasFrontmatter)
        XCTAssertEqual(stats.headingCount, 2)
        XCTAssertEqual(stats.linkCount, 2)       // 1 markdown link + 1 wikilink
        XCTAssertEqual(stats.taskCount, 2)
        XCTAssertTrue(stats.hasMath)
        XCTAssertGreaterThan(stats.wordCount, 5)
        XCTAssertGreaterThanOrEqual(stats.readTimeMinutes, 1)
    }

    func testSummariseWithoutFrontmatter() {
        let stats = MarkdownAnalyzer.summarise(source: "# H\nBody only.")
        XCTAssertFalse(stats.hasFrontmatter)
        XCTAssertFalse(stats.hasMath)
        XCTAssertEqual(stats.taskCount, 0)
    }

    // MARK: - Word count

    func testWordCount() {
        XCTAssertEqual(MarkdownAnalyzer.wordCount(in: ""), 0)
        XCTAssertEqual(MarkdownAnalyzer.wordCount(in: "one"), 1)
        XCTAssertEqual(MarkdownAnalyzer.wordCount(in: "one two three"), 3)
        XCTAssertEqual(MarkdownAnalyzer.wordCount(in: "  one\ntwo   three\n\n"), 3)
    }
}
