// MarkdownAnalyzer — regex + line-scan helpers for MarkdownRenderer.
// Pure logic, unit-testable without SwiftUI: heading extraction,
// wikilink detection, link/task/math heuristics, word counting,
// frontmatter stripping.

import Foundation

public struct MarkdownStats: Sendable, Hashable {
    public let wordCount: Int
    public let headingCount: Int
    public let linkCount: Int
    public let taskCount: Int
    public let hasFrontmatter: Bool
    public let hasMath: Bool
    public let readTimeMinutes: Int

    public init(
        wordCount: Int,
        headingCount: Int,
        linkCount: Int,
        taskCount: Int,
        hasFrontmatter: Bool,
        hasMath: Bool,
        readTimeMinutes: Int
    ) {
        self.wordCount = wordCount
        self.headingCount = headingCount
        self.linkCount = linkCount
        self.taskCount = taskCount
        self.hasFrontmatter = hasFrontmatter
        self.hasMath = hasMath
        self.readTimeMinutes = readTimeMinutes
    }
}

public enum MarkdownAnalyzer {

    // MARK: - Top-level summary

    public static func summarise(source: String) -> MarkdownStats {
        let (body, frontmatter) = stripFrontmatter(source)
        let headings = extractHeadings(from: body).count
        let links = countMatches(in: body, pattern: #"\[[^\]]+\]\([^)]+\)"#)
        let wikilinks = countMatches(in: body, pattern: #"\[\[[^\]]+\]\]"#)
        let tasks = countMatches(in: body, pattern: #"^[\-\*] \[[ x]\] "#, options: [.anchorsMatchLines])
        let mathInline = countMatches(in: body, pattern: #"\$[^\$]+\$"#)
        let mathBlock  = countMatches(in: body, pattern: #"\$\$[^\$]+\$\$"#, options: [.dotMatchesLineSeparators])

        let words = wordCount(in: body)
        let readTime = max(1, (words + 199) / 200)

        return MarkdownStats(
            wordCount: words,
            headingCount: headings,
            linkCount: links + wikilinks,
            taskCount: tasks,
            hasFrontmatter: frontmatter,
            hasMath: mathInline + mathBlock > 0,
            readTimeMinutes: readTime
        )
    }

    // MARK: - Frontmatter

    /// Returns `(body, hadFrontmatter)`. Only YAML-style (`---`) is
    /// recognised; TOML frontmatter `+++` is treated as body text
    /// because the body contract is "looks like prose" not "every
    /// Obsidian edge case".
    public static func stripFrontmatter(_ source: String) -> (body: String, had: Bool) {
        let trimmed = source.drop(while: { $0.isNewline })
        guard trimmed.hasPrefix("---\n") || trimmed.hasPrefix("---\r\n") else {
            return (source, false)
        }
        let lines = source.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return (source, false) }
        var end: Int?
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            end = i; break
        }
        guard let endIdx = end else { return (source, false) }
        let body = lines.dropFirst(endIdx + 1).joined(separator: "\n")
        return (body, true)
    }

    // MARK: - Heading outline

    /// Extract H1–H3 headings into `OutlineEntry` values with
    /// weightFraction assigned by character-range share.
    public static func extractHeadings(from source: String) -> [OutlineEntry] {
        // Pair each heading line with its starting character offset.
        struct Found { let level: Int; let title: String; let offset: Int }
        var finds: [Found] = []
        var offset = 0
        for line in source.components(separatedBy: .newlines) {
            if let match = parseHeading(line), match.level <= 3 {
                finds.append(Found(level: match.level,
                                   title: match.title,
                                   offset: offset))
            }
            offset += line.count + 1
        }
        guard !finds.isEmpty else { return [] }

        let totalChars = max(1, source.count)
        return finds.enumerated().map { (i, f) -> OutlineEntry in
            let end = i + 1 < finds.count ? finds[i + 1].offset : totalChars
            let span = max(1, end - f.offset)
            let fraction = min(1, Double(span) / Double(totalChars))
            return OutlineEntry(
                title: f.title,
                subtitle: "H\(f.level)",
                depth: f.level - 1,
                weightFraction: fraction,
                children: [],
                kind: .heading
            )
        }
    }

    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        var i = trimmed.startIndex
        while i < trimmed.endIndex, trimmed[i] == "#", level < 6 {
            level += 1
            i = trimmed.index(after: i)
        }
        guard i < trimmed.endIndex, trimmed[i] == " " else { return nil }
        let title = String(trimmed[trimmed.index(after: i)...])
            .trimmingCharacters(in: .whitespaces)
        return (level, title)
    }

    // MARK: - Wikilinks

    /// Extract `[[target]]` and `[[target|display]]` into relation
    /// descriptors. Each call yields a relation with
    /// `.wikiLinksTo` + the resolved display name.
    public static func extractWikilinks(from source: String) -> [CairnRelation] {
        let pattern = #"\[\[([^\]\|]+)(?:\|([^\]]+))?\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var out: [CairnRelation] = []
        regex.enumerateMatches(in: source, options: [], range: range) { m, _, _ in
            guard let m else { return }
            if let r = Range(m.range(at: 1), in: source) {
                let target = String(source[r])
                let display: String
                if m.numberOfRanges > 2, let r2 = Range(m.range(at: 2), in: source) {
                    display = String(source[r2])
                } else {
                    display = target
                }
                out.append(CairnRelation(
                    type: .wikiLinksTo,
                    targetDisplayName: display
                ))
                _ = target
            }
        }
        return out
    }

    // MARK: - Lead paragraph

    public static func firstParagraph(in source: String) -> String? {
        let (body, _) = stripFrontmatter(source)
        var accumulated = ""
        for line in body.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                if !accumulated.isEmpty { break }
                continue
            }
            // Skip headings and blockquotes — the lead should be
            // narrative prose.
            if stripped.hasPrefix("#") || stripped.hasPrefix(">") { continue }
            if accumulated.isEmpty {
                accumulated = stripped
            } else {
                accumulated += " " + stripped
            }
            if accumulated.count > 280 { break }
        }
        return accumulated.isEmpty ? nil : accumulated
    }

    // MARK: - Utilities

    public static func wordCount(in source: String) -> Int {
        source.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func countMatches(
        in source: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return 0
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.numberOfMatches(in: source, options: [], range: range)
    }
}
