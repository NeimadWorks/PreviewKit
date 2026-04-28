// CSVInspector — first-50-rows parser for CSV / TSV files. Column
// type inference (Int / Float / Date / String) runs off the first
// non-header rows. RFC 4180 quoting is respected for CSV.

import Foundation

public enum CSVColumnType: String, Sendable, Hashable {
    case integer, float, date, string, empty
}

public struct CSVSummary: Sendable, Hashable {
    public let separator: Character
    public let rowCount: Int
    public let columnCount: Int
    public let hasHeader: Bool
    public let headers: [String]
    public let columnTypes: [CSVColumnType]
    public let rowsPreview: [[String]]
    public let emptyPercentage: Double

    public init(
        separator: Character,
        rowCount: Int,
        columnCount: Int,
        hasHeader: Bool,
        headers: [String],
        columnTypes: [CSVColumnType],
        rowsPreview: [[String]],
        emptyPercentage: Double
    ) {
        self.separator = separator
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.hasHeader = hasHeader
        self.headers = headers
        self.columnTypes = columnTypes
        self.rowsPreview = rowsPreview
        self.emptyPercentage = emptyPercentage
    }
}

public enum CSVInspector {

    /// Parse a full CSV, capping the preview at `maxPreviewRows`.
    /// `separator` defaults to `,` for CSV, `\t` for TSV.
    public static func inspect(source: String,
                               separator: Character = ",",
                               maxPreviewRows: Int = 50) -> CSVSummary {
        let rows = parse(source: source, separator: separator)
        let header = detectHeader(rows)
        let columnCount = rows.map(\.count).max() ?? 0

        let dataStart = header ? 1 : 0
        let dataRows = Array(rows.dropFirst(dataStart))
        let columnTypes = inferTypes(dataRows: dataRows, columnCount: columnCount)
        let emptyCells = dataRows.reduce(0) { $0 + $1.filter(\.isEmpty).count }
        let totalCells = max(1, dataRows.count * columnCount)
        let emptyPct = Double(emptyCells) / Double(totalCells)

        return CSVSummary(
            separator: separator,
            rowCount: rows.count,
            columnCount: columnCount,
            hasHeader: header,
            headers: header ? rows[0] : (0..<columnCount).map { "Column \($0 + 1)" },
            columnTypes: columnTypes,
            rowsPreview: Array(rows.prefix(maxPreviewRows)),
            emptyPercentage: emptyPct
        )
    }

    /// RFC-4180-ish CSV row parser. Handles quoted fields with
    /// embedded separators, `""` escapes, and trailing empty fields.
    /// Exposed so tests can pin formatting edge cases.
    public static func parse(source: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = source.startIndex

        while i < source.endIndex {
            let ch = source[i]
            if inQuotes {
                if ch == "\"" {
                    let next = source.index(after: i)
                    if next < source.endIndex, source[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                if ch == "\"", field.isEmpty {
                    inQuotes = true
                } else if ch == separator {
                    current.append(field)
                    field = ""
                } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                    if ch == "\r", source.index(after: i) < source.endIndex,
                       source[source.index(after: i)] == "\n" {
                        i = source.index(after: i)
                    }
                } else {
                    field.append(ch)
                }
            }
            i = source.index(after: i)
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }

    /// Heuristic: if row 0 has any cell that can't be parsed as a
    /// number AND row 1 exists with predominantly numeric cells, row 0
    /// is a header.
    public static func detectHeader(_ rows: [[String]]) -> Bool {
        guard rows.count >= 2 else { return false }
        let row0Numeric = rows[0].filter { Double($0) != nil }.count
        let row0Alpha   = rows[0].filter { $0.rangeOfCharacter(from: .letters) != nil }.count
        let row1Numeric = rows[1].filter { Double($0) != nil }.count
        return row0Alpha > row0Numeric && row1Numeric > 0
    }

    /// Per-column type inference. The column type is the most specific
    /// type that fits every non-empty cell.
    public static func inferTypes(dataRows: [[String]], columnCount: Int) -> [CSVColumnType] {
        var out: [CSVColumnType] = []
        out.reserveCapacity(columnCount)
        let df = ISO8601DateFormatter()
        let df2 = DateFormatter()
        df2.dateFormat = "yyyy-MM-dd"
        df2.locale = Locale(identifier: "en_US_POSIX")

        for col in 0..<columnCount {
            var allInt = true, allFloat = true, allDate = true, anyValue = false
            for row in dataRows {
                guard col < row.count else { continue }
                let cell = row[col].trimmingCharacters(in: .whitespaces)
                if cell.isEmpty { continue }
                anyValue = true
                if Int(cell) == nil { allInt = false }
                if Double(cell) == nil { allFloat = false }
                if df.date(from: cell) == nil && df2.date(from: cell) == nil { allDate = false }
                if !allFloat && !allDate { break }
            }
            let t: CSVColumnType
            if !anyValue           { t = .empty }
            else if allInt         { t = .integer }
            else if allFloat       { t = .float }
            else if allDate        { t = .date }
            else                   { t = .string }
            out.append(t)
        }
        return out
    }
}
