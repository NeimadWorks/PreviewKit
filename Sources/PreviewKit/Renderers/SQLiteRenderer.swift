// SQLiteRenderer — opens a SQLite database read-only, lists schema,
// previews the largest table, and identifies known applications via
// `AppSignatureRegistry` (Safari history, iMessage, Photos, Notes…).
//
// Origin: Canopy's `SQLiteInspectorHero` (Plugins/Documents/DocumentsHeroViews.swift),
// merged into PreviewKit on extraction. The schema introspection runs
// against a temp URL — large databases stay on disk and only metadata
// loads into memory.

import SwiftUI
import SQLite3

public struct SQLiteRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.sqlite] }
    public static var priority: Int { 0 }
    public static func make() -> SQLiteRenderer { SQLiteRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(SQLiteRendererBody(item: item, data: data, url: url))
    }
}

private struct SQLiteRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var tables: [TableInfo] = []
    @State private var indexCount: Int = 0
    @State private var estimatedRows: Int = 0
    @State private var detectedApp: AppSignature?
    @State private var journalMode: String = ""
    @State private var integrityOK: Bool?
    @State private var dbSizeBreakdown: String = ""
    @State private var dbEncoding: String = ""
    @State private var previewColumns: [String] = []
    @State private var previewRows: [[String]] = []
    @State private var outline: [OutlineEntry] = []
    @State private var loadError: String?
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let detectedApp {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(PreviewTokens.mimeColor(for: .data))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detectedApp.appName).font(PreviewTokens.fontHeader)
                            Text(detectedApp.description)
                                .font(PreviewTokens.fontLabel)
                                .foregroundStyle(PreviewTokens.textMuted)
                        }
                    }
                }

                if isLoaded {
                    KPITileRow(kpiTiles, columns: 4)
                }

                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }

                if !outline.isEmpty {
                    Text("Schema")
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .textCase(.uppercase)
                    StructureOutlineView(
                        entries: outline,
                        storageKey: "sqlite.\(item.id.uuidString)"
                    )
                }

                if !previewColumns.isEmpty && !previewRows.isEmpty {
                    tablePreview
                }

                if isLoaded { metadataGrid }

                if let loadError {
                    Text(loadError)
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(.red)
                }
            }
            .padding(PreviewTokens.cardPadding)
        }
        .task(id: item.id) { await loadIfNeeded() }
        .background(PreviewTokens.bgPrimary)
    }

    private var kpiTiles: [KPITile] {
        var tiles: [KPITile] = [
            KPITile(value: "\(tables.count)", label: "Tables"),
            KPITile(value: formatCompact(estimatedRows), label: "Est. rows"),
        ]
        if indexCount > 0 {
            tiles.append(KPITile(value: "\(indexCount)", label: "Indexes"))
        }
        if !journalMode.isEmpty {
            tiles.append(KPITile(value: journalMode.uppercased(), label: "Journal"))
        }
        return tiles
    }

    private var badges: [SemanticBadgeModel] {
        var b: [SemanticBadgeModel] = []
        if journalMode.lowercased() == "wal" {
            b.append(SemanticBadgeModel(text: "WAL", style: .info))
        }
        if let ok = integrityOK {
            b.append(SemanticBadgeModel(
                text: ok ? "Integrity OK" : "Corrupted",
                style: ok ? .success : .danger
            ))
        }
        if !dbEncoding.isEmpty {
            b.append(SemanticBadgeModel(text: dbEncoding, style: .neutral))
        }
        return b
    }

    @ViewBuilder
    private var tablePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(previewColumns.enumerated()), id: \.offset) { _, col in
                            Text(col)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                    }
                    Divider()
                    ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, val in
                                Text(val)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 96, alignment: .leading)
                                    .lineLimit(1)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(PreviewTokens.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd))
        }
    }

    @ViewBuilder
    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            metaRow("Database size", dbSizeBreakdown)
            if let detectedApp, let bundle = detectedApp.bundleIdentifier {
                metaRow("Bundle", bundle)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(PreviewTokens.fontLabel).foregroundStyle(PreviewTokens.textMuted)
            Spacer()
            Text(value).font(PreviewTokens.fontLabel)
        }
    }

    // MARK: - Load

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        // Resolve a path on disk. SQLiteRenderer needs a real file —
        // synthesise a temp URL from `data` if the host didn't supply one.
        var path: String?
        if let url { path = url.path }
        else if let data {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("pkit-\(item.id.uuidString).sqlite")
            try? data.write(to: tmp)
            path = tmp.path
        }
        guard let path else {
            loadError = "No data available"
            return
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            loadError = "Couldn't open database"
            return
        }
        defer { sqlite3_close(db) }

        // Tables
        let tableNames = queryColumn(db: db, sql: """
            SELECT name FROM sqlite_master
            WHERE type='table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
            """)
        let indexNames = queryColumn(db: db, sql: "SELECT name FROM sqlite_master WHERE type='index'")
        indexCount = indexNames.count

        // App fingerprint
        let nameSet = Set(tableNames.map { $0.lowercased() })
        detectedApp = AppSignatureRegistry.match(tables: nameSet)

        // Schema + estimated rows
        var tableInfos: [TableInfo] = []
        var entries: [OutlineEntry] = []
        var maxRows = 0
        for name in tableNames {
            let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
            let cols = queryColumns(db: db, table: escaped)
            tableInfos.append(TableInfo(name: name, columns: cols))

            let kids = cols.map { col -> OutlineEntry in
                let title = col.isPK ? "🔑 \(col.name)" : col.name
                let sub = col.type.isEmpty ? nil : col.type
                return OutlineEntry(title: title, subtitle: sub, depth: 1, kind: .property)
            }
            entries.append(OutlineEntry(title: name, depth: 0, children: kids, kind: .table))

            let rows = queryColumn(db: db, sql: "SELECT MAX(rowid) FROM \"\(escaped)\"")
            if let n = rows.first.flatMap(Int.init) { maxRows = max(maxRows, n) }
        }
        tables = tableInfos
        outline = entries
        estimatedRows = maxRows

        // Preview: pick the biggest-by-column-count table
        if let biggest = tableInfos.max(by: { $0.columns.count < $1.columns.count }) {
            let escaped = biggest.name.replacingOccurrences(of: "\"", with: "\"\"")
            previewColumns = Array(biggest.columns.prefix(5).map(\.name))
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT * FROM \"\(escaped)\" LIMIT 5", -1, &stmt, nil) == SQLITE_OK {
                let n = min(Int(sqlite3_column_count(stmt)), 5)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    var row: [String] = []
                    for i in 0..<Int32(n) {
                        if let txt = sqlite3_column_text(stmt, i) {
                            row.append(String(String(cString: txt).prefix(20)))
                        } else {
                            row.append("NULL")
                        }
                    }
                    previewRows.append(row)
                }
            }
            sqlite3_finalize(stmt)
        }

        journalMode = queryColumn(db: db, sql: "PRAGMA journal_mode").first ?? ""
        dbEncoding = queryColumn(db: db, sql: "PRAGMA encoding").first ?? ""

        // Integrity quick check (only for files < 500 MB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64, size < 500_000_000 {
            integrityOK = queryColumn(db: db, sql: "PRAGMA quick_check").first?.lowercased() == "ok"
        }

        // Size breakdown
        let pc = queryColumn(db: db, sql: "PRAGMA page_count").first.flatMap(Int64.init)
        let ps = queryColumn(db: db, sql: "PRAGMA page_size").first.flatMap(Int64.init)
        if let pc, let ps {
            dbSizeBreakdown = ByteCountFormatter.string(fromByteCount: pc * ps, countStyle: .file)
                + " (\(pc) pages × \(ps) bytes)"
        }

        isLoaded = true
    }

    private func queryColumn(db: OpaquePointer?, sql: String) -> [String] {
        var stmt: OpaquePointer?
        var out: [String] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let txt = sqlite3_column_text(stmt, 0) {
                out.append(String(cString: txt))
            }
        }
        return out
    }

    private func queryColumns(db: OpaquePointer?, table: String) -> [ColumnInfo] {
        var stmt: OpaquePointer?
        var cols: [ColumnInfo] = []
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table)\")", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let isPK = sqlite3_column_int(stmt, 5) > 0
            cols.append(ColumnInfo(name: name, type: type, isPK: isPK))
        }
        return cols
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Models

private struct TableInfo: Hashable {
    let name: String
    let columns: [ColumnInfo]
}

private struct ColumnInfo: Hashable {
    let name: String
    let type: String
    let isPK: Bool
}
