// WebShortcutRenderer — `.webloc` (XML plist) and `.url` (INI-style)
// shortcuts. Resolves the destination URL, derives the host, flags
// HTTPS/HTTP, IP-host, and tracking parameters via URLSecurityRegistry.
//
// Origin: Canopy's `WebShortcutInspectorHero`, merged on extraction.

import SwiftUI

public struct WebShortcutRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.webShortcut] }
    public static var priority: Int { 0 }
    public static func make() -> WebShortcutRenderer { WebShortcutRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(WebShortcutRendererBody(item: item, data: data, url: url))
    }
}

private struct WebShortcutRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var destination: URL?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let destination {
                    Text(destination.absoluteString)
                        .font(PreviewTokens.fontBody.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .foregroundStyle(PreviewTokens.textMuted)
                        Text(destination.host ?? "(no host)")
                            .font(PreviewTokens.fontHeader)
                    }

                    SemanticBadgeRow(badges(for: destination))

                    if URLSecurityRegistry.hasTracking(destination) {
                        let stripped = URLSecurityRegistry.stripTracking(from: destination)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Without tracking")
                                .font(PreviewTokens.fontLabel)
                                .foregroundStyle(PreviewTokens.textMuted)
                                .textCase(.uppercase)
                            Text(stripped.absoluteString)
                                .font(PreviewTokens.fontBody.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else {
                    ProgressView("Reading…").frame(maxWidth: .infinity)
                }
            }
            .padding(PreviewTokens.cardPadding)
        }
        .task(id: item.id) { await load() }
        .background(PreviewTokens.bgPrimary)
    }

    private func badges(for url: URL) -> [SemanticBadgeModel] {
        var b: [SemanticBadgeModel] = []
        if url.scheme == "https" {
            b.append(SemanticBadgeModel(text: "HTTPS", style: .success, icon: "lock.fill"))
        } else if url.scheme == "http" {
            b.append(SemanticBadgeModel(text: "HTTP", style: .danger, icon: "lock.open"))
        }
        if let host = url.host, URLSecurityRegistry.isDomainIP(host) {
            b.append(SemanticBadgeModel(text: "IP host", style: .warning))
        }
        if URLSecurityRegistry.hasTracking(url) {
            b.append(SemanticBadgeModel(text: "Tracking", style: .warning, icon: "eye"))
        }
        return b
    }

    // MARK: - Load

    private func load() async {
        let bytes: Data?
        if let data { bytes = data }
        else if let url { bytes = try? Data(contentsOf: url) }
        else { bytes = nil }
        guard let bytes else {
            loadError = "Couldn't read shortcut"
            return
        }

        // Two formats:
        //   .webloc → XML plist with key "URL"
        //   .url    → INI: lines like "URL=https://…"
        let ext = (item.fileExtension ?? "").lowercased()
        if ext == "webloc" {
            destination = parseWebloc(bytes)
        } else if ext == "url" {
            destination = parseURLFile(bytes)
        } else {
            // Try both
            destination = parseWebloc(bytes) ?? parseURLFile(bytes)
        }
        if destination == nil { loadError = "Couldn't parse shortcut" }
    }

    private func parseWebloc(_ data: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any],
              let urlString = plist["URL"] as? String
        else { return nil }
        return URL(string: urlString)
    }

    private func parseURLFile(_ data: Data) -> URL? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.uppercased().hasPrefix("URL=") {
                return URL(string: String(t.dropFirst(4)))
            }
        }
        return nil
    }
}
