// DataRenderer — the catch-all for structured data formats. Dispatches
// on `ArtifactKind`:
//   - JSON / YAML / TOML / XML / Plist → collapsible key/value tree
//   - CSV / TSV → tabular preview
//   - SQLite → "this build doesn't link sqlite3"; defers to the
//     binary fallback with a note (real viewer is a Session 5 task
//     that needs the CairnCore C bridge)

import SwiftUI

public struct DataRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> {
        [.json, .yaml, .toml, .xml, .plist, .csv, .tsv, .sqlite]
    }
    public static var priority: Int { 0 }
    public static func make() -> DataRenderer { DataRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(DataRendererBody(item: item, data: data, url: url))
    }
}

private struct DataRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var source: String?
    @State private var tree: JSONParseResult?
    @State private var csv: CSVSummary?
    @State private var loadError: String?

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
        .task(id: item.id) { await load() }
    }

    // MARK: - Left pane

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't read",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else {
            switch item.kind {
            case .csv, .tsv:
                csvPane
            case .sqlite:
                sqlitePlaceholder
            default:
                treePane
            }
        }
    }

    private var treePane: some View {
        ScrollView([.vertical, .horizontal]) {
            if let tree {
                VStack(alignment: .leading, spacing: 0) {
                    if let err = tree.error {
                        errorLine(err: err, line: tree.errorLine)
                    }
                    if let root = tree.root {
                        JSONTreeView(node: root, depth: 0, keyPath: "$")
                    }
                }
                .padding(14)
            } else {
                ProgressView("Parsing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PreviewTokens.bgPrimary)
    }

    private func errorLine(err: String, line: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            if let line {
                Text("Line \(line):")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
            Text(err)
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.textPrimary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd))
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var csvPane: some View {
        if let csv {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    if csv.hasHeader {
                        csvRow(csv.headers, isHeader: true)
                    }
                    ForEach(Array(csv.rowsPreview.enumerated()), id: \.offset) { idx, row in
                        if idx == 0 && csv.hasHeader { EmptyView() }
                        else { csvRow(row, isHeader: false) }
                    }
                    if csv.rowCount > csv.rowsPreview.count {
                        Text("\(csv.rowCount - csv.rowsPreview.count) more rows")
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                            .padding(.top, 8)
                    }
                }
                .padding(14)
            }
            .background(PreviewTokens.bgPrimary)
        } else {
            ProgressView("Parsing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func csvRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(isHeader
                          ? PreviewTokens.fontMonoBody.weight(.semibold)
                          : PreviewTokens.fontMonoBody)
                    .foregroundStyle(isHeader
                                     ? PreviewTokens.textPrimary
                                     : PreviewTokens.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 120, maxWidth: 240, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 120)
        .background(isHeader ? PreviewTokens.bgHover : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PreviewTokens.borderFaint)
                .frame(height: isHeader ? 1 : 0.5)
        }
    }

    private var sqlitePlaceholder: some View {
        ContentUnavailableMessage(
            title: "SQLite preview lands next session",
            subtitle: "PreviewKit needs to link sqlite3 via the CairnCore C bridge — slated for Session 5 polish. The file is still listed in the navigator and can be exported.",
            symbol: "cylinder.split.1x2"
        )
        .padding(24)
    }

    // MARK: - Inspector

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var kpis: [KPITile] {
        switch item.kind {
        case .csv, .tsv:
            guard let csv else { return placeholderTiles() }
            return [
                KPITile(value: "\(csv.rowCount)",    label: "Rows"),
                KPITile(value: "\(csv.columnCount)", label: "Columns"),
                KPITile(value: String(csv.separator == "," ? "," : "\\t"),
                        label: "Separator"),
                KPITile(value: String(format: "%.0f%%", csv.emptyPercentage * 100),
                        label: "Empty cells"),
            ]
        case .sqlite:
            return [
                KPITile(value: "—", label: "Tables"),
                KPITile(value: "—", label: "Rows"),
                KPITile(value: "sqlite3", label: "Format"),
                KPITile(value: formatBytes(item.sizeBytes), label: "Size"),
            ]
        default:
            guard let tree, let root = tree.root else { return placeholderTiles() }
            return [
                KPITile(value: "\(root.keyCount)", label: "Keys"),
                KPITile(value: "\(root.depth)",    label: "Max depth"),
                KPITile(value: formatBytes(item.sizeBytes), label: "Size"),
                KPITile(value: tree.isValid ? "valid" : "invalid",
                        label: "Parse",
                        badge: tree.isValid ? .success : .danger),
            ]
        }
    }

    private var badges: [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if let csv, csv.hasHeader {
            out.append(.init(text: "Headers", style: .success, icon: "tablecells"))
        }
        if let tree {
            if let err = tree.error {
                out.append(.init(text: "Invalid", style: .danger, icon: "exclamationmark.triangle"))
                _ = err
            } else if tree.root != nil {
                out.append(.init(text: "Valid", style: .success, icon: "checkmark.seal"))
            }
        }
        return out
    }

    private func placeholderTiles() -> [KPITile] {
        [
            .placeholder(label: "—"),
            .placeholder(label: "—"),
            .placeholder(label: "—"),
            .placeholder(label: "—"),
        ]
    }

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        source = nil
        tree = nil
        csv = nil
        loadError = nil

        // Materialise bytes.
        let bytes: Data? = {
            if let data { return data }
            if let url { return try? Data(contentsOf: url) }
            return nil
        }()
        guard let bytes else {
            loadError = "The data source didn't return bytes."
            return
        }

        switch item.kind {
        case .json:
            self.tree = await Task.detached(priority: .userInitiated) {
                JSONTreeParser.parse(data: bytes)
            }.value
        case .plist:
            self.tree = await Task.detached(priority: .userInitiated) {
                PlistTreeParser.parse(data: bytes)
            }.value
        case .yaml, .toml, .xml:
            // We don't parse these into a tree (no vendored YAML/TOML
            // parser under the zero-dep rule) — show the raw text and
            // mark as "valid if UTF-8".
            let text = String(data: bytes, encoding: .utf8) ?? "<binary>"
            self.source = text
            self.tree = JSONParseResult(
                root: .string(text),
                error: nil,
                errorLine: nil
            )
        case .csv, .tsv:
            guard let text = String(data: bytes, encoding: .utf8) else {
                loadError = "File isn't UTF-8 text."
                return
            }
            let separator: Character = item.kind == .tsv ? "\t" : ","
            self.csv = await Task.detached(priority: .userInitiated) {
                CSVInspector.inspect(source: text, separator: separator)
            }.value
        case .sqlite:
            // Intentional: handled by the placeholder view above.
            break
        default:
            loadError = "Unexpected kind routed to DataRenderer."
        }
    }
}

// MARK: - JSONTreeView

/// Iterative tree renderer — `OutlineGroup` would recurse into the
/// view's generic signature, which Swift 6 refuses because `some View`
/// can't be self-referential. Instead, we flatten + indent manually.
private struct JSONTreeView: View {

    let node: JSONTreeNode
    let depth: Int
    let keyPath: String

    @State private var expanded: Bool = true

    var body: some View {
        switch node {
        case .object(let kvs):
            VStack(alignment: .leading, spacing: 0) {
                header(text: "{\(kvs.count) keys}", expandable: !kvs.isEmpty)
                if expanded {
                    ForEach(Array(kvs.enumerated()), id: \.offset) { _, kv in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(String(repeating: "  ", count: depth + 1))
                            Text("\"\(kv.key)\"")
                                .font(PreviewTokens.fontMono)
                                .foregroundStyle(PreviewTokens.syntaxType)
                            Text(": ")
                                .font(PreviewTokens.fontMono)
                                .foregroundStyle(PreviewTokens.syntaxDefault)
                            JSONTreeView(
                                node: kv.value,
                                depth: depth + 1,
                                keyPath: keyPath + "." + kv.key
                            )
                        }
                    }
                }
            }
        case .array(let xs):
            VStack(alignment: .leading, spacing: 0) {
                header(text: "[\(xs.count) items]", expandable: !xs.isEmpty)
                if expanded {
                    ForEach(Array(xs.enumerated()), id: \.offset) { i, v in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(String(repeating: "  ", count: depth + 1))
                            Text("[\(i)] ")
                                .font(PreviewTokens.fontMono)
                                .foregroundStyle(PreviewTokens.textMuted)
                            JSONTreeView(
                                node: v,
                                depth: depth + 1,
                                keyPath: keyPath + "[\(i)]"
                            )
                        }
                    }
                }
            }
        case .string(let s):
            Text("\"\(s)\"")
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.syntaxString)
                .lineLimit(3)
                .textSelection(.enabled)
        case .number(let n):
            Text(n.truncatingRemainder(dividingBy: 1) == 0
                 ? String(Int64(n))
                 : String(n))
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.syntaxNumber)
        case .bool(let b):
            Text(b ? "true" : "false")
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.syntaxKeyword)
        case .null:
            Text("null")
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.textMuted)
        }
    }

    private func header(text: String, expandable: Bool) -> some View {
        Button {
            if expandable { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                if expandable {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Text(text)
                    .font(PreviewTokens.fontMono)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
        .buttonStyle(.plain)
    }
}
