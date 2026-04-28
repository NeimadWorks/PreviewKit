// PatchAnalyzer — pure unified-diff parsing helpers.
//
// Accepts the output of `git diff`, `diff -u`, `svn diff`. Line-oriented,
// tolerant of leading mail headers ("From ", "Subject:") and trailing
// signatures. Only the `--- / +++` and `@@` control lines drive state.

import Foundation

public struct PatchStats: Sendable, Equatable {
    public var filesChanged: Int
    public var additions: Int
    public var deletions: Int
    public var hunks: Int
    public var hasBinaryPatch: Bool
    public var hasRename: Bool
    public var hasNewFile: Bool
    public var hasDeletedFile: Bool
    public var files: [String]
}

public enum PatchLineKind: Sendable, Equatable {
    case context
    case addition
    case deletion
    case hunkHeader
    case fileHeader
    case meta
}

public enum PatchAnalyzer {

    /// Classify a single line of a unified diff.
    public static func classify(_ line: String) -> PatchLineKind {
        if line.hasPrefix("@@") { return .hunkHeader }
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .fileHeader }
        if line.hasPrefix("diff ") || line.hasPrefix("index ")
            || line.hasPrefix("rename ") || line.hasPrefix("new file ")
            || line.hasPrefix("deleted file ") || line.hasPrefix("similarity ")
            || line.hasPrefix("Binary ") || line.hasPrefix("GIT binary patch") {
            return .meta
        }
        // `+` / `-` after the file-header section.
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .deletion }
        return .context
    }

    /// Parse the full patch. Cheap — single pass, string split only.
    public static func parse(_ source: String) -> PatchStats {
        var s = PatchStats(
            filesChanged: 0, additions: 0, deletions: 0, hunks: 0,
            hasBinaryPatch: false, hasRename: false,
            hasNewFile: false, hasDeletedFile: false, files: []
        )
        var seenFiles = Set<String>()

        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("@@") {
                s.hunks += 1
                continue
            }
            if line.hasPrefix("+++ ") {
                let name = extractFileName(from: line.dropFirst(4))
                if !name.isEmpty, seenFiles.insert(name).inserted {
                    s.files.append(name)
                    s.filesChanged += 1
                }
                continue
            }
            if line.hasPrefix("--- ") {
                continue  // consumed by the matching +++
            }
            if line.hasPrefix("GIT binary patch") || line.hasPrefix("Binary files ") {
                s.hasBinaryPatch = true
                continue
            }
            if line.hasPrefix("rename from ") || line.hasPrefix("rename to ") {
                s.hasRename = true
                continue
            }
            if line.hasPrefix("new file mode") {
                s.hasNewFile = true
                continue
            }
            if line.hasPrefix("deleted file mode") {
                s.hasDeletedFile = true
                continue
            }
            // Bare +/- lines count only when they're not file headers.
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                s.additions += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                s.deletions += 1
            }
        }
        return s
    }

    /// Best-effort filename extraction from the right-hand side of a
    /// `+++` header: `+++ b/path/to/file.swift\t2026-04-18 ...`.
    private static func extractFileName(from segment: Substring) -> String {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        // Drop trailing timestamp after tab, if any.
        let upToTab = trimmed.split(separator: "\t").first.map(String.init) ?? trimmed
        // git uses `a/` / `b/` prefixes; strip one.
        if upToTab.hasPrefix("b/") || upToTab.hasPrefix("a/") {
            return String(upToTab.dropFirst(2))
        }
        if upToTab == "/dev/null" { return "" }
        return upToTab
    }
}
