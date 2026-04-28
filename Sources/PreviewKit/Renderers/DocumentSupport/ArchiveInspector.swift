// ArchiveInspector — shells to `/usr/bin/unzip -l` or `/usr/bin/tar
// -tvf` to list entries. Parsed into `ArchiveEntry` rows with name,
// compressed/uncompressed sizes, and family-inferred MIME bar input.
//
// We deliberately don't pull in libarchive or similar — the zero-dep
// rule still stands, and the system tools have been stable for
// decades.

import Foundation

public struct ArchiveEntry: Sendable, Hashable, Identifiable {
    public let id: UUID = UUID()
    public let name: String
    public let uncompressedBytes: Int64
    public let compressedBytes: Int64

    public init(name: String, uncompressedBytes: Int64, compressedBytes: Int64) {
        self.name = name
        self.uncompressedBytes = uncompressedBytes
        self.compressedBytes = compressedBytes
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var family: ArtifactKind.Family {
        ArtifactKind.infer(fromExtension: fileExtension).family
    }

    public var ratio: Double {
        guard uncompressedBytes > 0 else { return 0 }
        return Double(compressedBytes) / Double(uncompressedBytes)
    }
}

public struct ArchiveSummary: Sendable, Hashable {
    public let format: String
    public let entryCount: Int
    public let uncompressedBytes: Int64
    public let compressedBytes: Int64
    public let topEntries: [ArchiveEntry]
    public let mimeSegments: [MIMESegment]
    public let hasPasswordProtection: Bool
    public let hasNested: Bool

    public init(
        format: String, entryCount: Int,
        uncompressedBytes: Int64, compressedBytes: Int64,
        topEntries: [ArchiveEntry], mimeSegments: [MIMESegment],
        hasPasswordProtection: Bool, hasNested: Bool
    ) {
        self.format = format
        self.entryCount = entryCount
        self.uncompressedBytes = uncompressedBytes
        self.compressedBytes = compressedBytes
        self.topEntries = topEntries
        self.mimeSegments = mimeSegments
        self.hasPasswordProtection = hasPasswordProtection
        self.hasNested = hasNested
    }

    public var ratio: Double {
        guard uncompressedBytes > 0 else { return 0 }
        return Double(compressedBytes) / Double(uncompressedBytes)
    }
}

public enum ArchiveInspector {

    public static func summarise(fileURL: URL, maxListed: Int = 200) throws -> ArchiveSummary {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "zip":
            return try unzipSummary(at: fileURL, maxListed: maxListed)
        case "tar", "tgz", "gz", "bz2", "xz":
            return try tarSummary(at: fileURL, maxListed: maxListed)
        default:
            return try unzipSummary(at: fileURL, maxListed: maxListed)
        }
    }

    // MARK: - ZIP

    public static func unzipSummary(at url: URL, maxListed: Int) throws -> ArchiveSummary {
        // `unzip -l -qq file.zip` columns: size, date, time, name
        // We also run `-Z` for compressed-size info.
        let detailed = try runProcess(
            "/usr/bin/unzip",
            ["-l", url.path]
        )
        let compressed = try? runProcess("/usr/bin/unzip", ["-Z", "-l", url.path])

        var entries = parseUnzipLines(detailed)
        let compressedLookup = parseUnzipCompressedLines(compressed ?? "")
        entries = entries.map { entry in
            let compBytes = compressedLookup[entry.name] ?? entry.uncompressedBytes
            return ArchiveEntry(name: entry.name,
                                uncompressedBytes: entry.uncompressedBytes,
                                compressedBytes: compBytes)
        }

        let listed = Array(entries.prefix(maxListed))
        let uncTotal = entries.reduce(Int64(0)) { $0 + $1.uncompressedBytes }
        let compTotal = entries.reduce(Int64(0)) { $0 + $1.compressedBytes }
        let segments = mimeSegments(for: entries)
        let nested = entries.contains { e in
            let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]
            return archiveExts.contains(e.fileExtension)
        }
        return ArchiveSummary(
            format: "ZIP",
            entryCount: entries.count,
            uncompressedBytes: uncTotal,
            compressedBytes: compTotal,
            topEntries: listed,
            mimeSegments: segments,
            hasPasswordProtection: detailed.contains("Archive: ") && detailed.contains("encrypted"),
            hasNested: nested
        )
    }

    /// Parse the "        size  date  time  name" middle rows of
    /// `unzip -l`. Header and footer lines are skipped.
    public static func parseUnzipLines(_ raw: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Middle rows start with a digit (the size).
            guard let first = trimmed.first, first.isNumber else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 4,
                  let size = Int64(parts[0]) else { continue }
            // Name is the tail after date + time (parts[1] + parts[2]).
            let nameStartIndex = 3
            let name = parts[nameStartIndex...].joined(separator: " ")
            entries.append(ArchiveEntry(name: name,
                                        uncompressedBytes: size,
                                        compressedBytes: size))
        }
        return entries
    }

    /// Parse `unzip -Z -l` where each entry line has method, CRC, etc.
    public static func parseUnzipCompressedLines(_ raw: String) -> [String: Int64] {
        var map: [String: Int64] = [:]
        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            // Heuristic: name must contain '.' or '/', compressed size
            // is the 2nd column on Zip entry rows.
            guard parts.count >= 8 else { continue }
            let last = parts[parts.count - 1]
            guard last.contains(".") || last.contains("/") else { continue }
            if let compressed = Int64(parts[1]) {
                map[last] = compressed
            }
        }
        return map
    }

    // MARK: - TAR

    public static func tarSummary(at url: URL, maxListed: Int) throws -> ArchiveSummary {
        let raw = try runProcess("/usr/bin/tar", ["-tvf", url.path])
        let entries = parseTarLines(raw)
        let listed = Array(entries.prefix(maxListed))
        let uncTotal = entries.reduce(Int64(0)) { $0 + $1.uncompressedBytes }
        let segments = mimeSegments(for: entries)
        let nested = entries.contains { e in
            let ext: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]
            return ext.contains(e.fileExtension)
        }
        return ArchiveSummary(
            format: "TAR",
            entryCount: entries.count,
            uncompressedBytes: uncTotal,
            compressedBytes: uncTotal,   // tar listings don't give per-entry compressed size
            topEntries: listed,
            mimeSegments: segments,
            hasPasswordProtection: false,
            hasNested: nested
        )
    }

    public static func parseTarLines(_ raw: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let months: Set<String> = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Canonical `tar -tvf` row:
            //   perms links owner group size date time name
            //
            // The size column is always the token immediately before a
            // month abbreviation — more reliable than guessing by
            // column index (BSD/GNU tar differ).
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 6,
                  let monthIdx = parts.firstIndex(where: { months.contains($0) }),
                  monthIdx > 0,
                  let size = Int64(parts[monthIdx - 1]) else { continue }
            let name = parts[parts.count - 1]
            entries.append(ArchiveEntry(name: name,
                                        uncompressedBytes: size,
                                        compressedBytes: size))
        }
        return entries
    }

    // MARK: - Helpers

    public static func mimeSegments(for entries: [ArchiveEntry]) -> [MIMESegment] {
        var bytesByFamily: [ArtifactKind.Family: Int64] = [:]
        var total: Int64 = 0
        for e in entries {
            let bytes = max(1, e.uncompressedBytes)
            bytesByFamily[e.family, default: 0] += bytes
            total += bytes
        }
        guard total > 0 else { return [] }
        return bytesByFamily
            .sorted(by: { $0.value > $1.value })
            .map { (family, bytes) in
                MIMESegment(
                    label: family.displayLabel,
                    fraction: Double(bytes) / Double(total),
                    family: family
                )
            }
    }

    private static func runProcess(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
