// ContactRenderer — parses `.vcf` (RFC 6350) and renders an avatar
// (PHOTO field or initials), name, organisation, multiple typed phones
// /emails/addresses, and a multi-contact navigator if the file has more
// than one VCARD block.
//
// Origin: Canopy's `ContactInspectorHero`, merged on extraction.
// Type-label translation via `VCardMappings`.

import SwiftUI
import AppKit

public struct ContactRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.vCard] }
    public static var priority: Int { 0 }
    public static func make() -> ContactRenderer { ContactRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(ContactRendererBody(item: item, data: data, url: url))
    }
}

private struct ContactRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var contacts: [ParsedContact] = []
    @State private var index: Int = 0
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let contact = contacts[safe: index] {
                    header(contact)
                    if !contact.phones.isEmpty {
                        section(title: "Phones", rows: contact.phones.map { ($0.label, $0.value) })
                    }
                    if !contact.emails.isEmpty {
                        section(title: "Emails", rows: contact.emails.map { ($0.label, $0.value) })
                    }
                    if !contact.addresses.isEmpty {
                        section(title: "Addresses", rows: contact.addresses.map { ($0.label, $0.value) })
                    }
                    if contacts.count > 1 { navigation }
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

    @ViewBuilder
    private func header(_ contact: ParsedContact) -> some View {
        HStack(alignment: .center, spacing: 14) {
            avatar(for: contact)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.fullName.isEmpty ? "(no name)" : contact.fullName)
                    .font(PreviewTokens.fontHeader)
                if let org = contact.organisation, !org.isEmpty {
                    Text(org)
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                }
                if let title = contact.title, !title.isEmpty {
                    Text(title)
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func avatar(for contact: ParsedContact) -> some View {
        if let photo = contact.photo, let nsImage = NSImage(data: photo) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(PreviewTokens.mimeColor(for: .documents).opacity(0.2))
                .overlay(
                    Text(contact.initials)
                        .font(PreviewTokens.fontHeader)
                        .foregroundStyle(PreviewTokens.mimeColor(for: .documents))
                )
        }
    }

    private func section(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
                .textCase(.uppercase)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.0)
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .frame(width: 70, alignment: .trailing)
                    Text(row.1)
                        .font(PreviewTokens.fontBody)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var navigation: some View {
        HStack {
            Button("←") { index = max(0, index - 1) }
                .disabled(index == 0)
            Text("Contact \(index + 1) / \(contacts.count)")
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
            Button("→") { index = min(contacts.count - 1, index + 1) }
                .disabled(index >= contacts.count - 1)
        }
    }

    // MARK: - Parsing

    private func load() async {
        let bytes: Data?
        if let data { bytes = data }
        else if let url { bytes = try? Data(contentsOf: url) }
        else { bytes = nil }
        guard let bytes, let text = String(data: bytes, encoding: .utf8) else {
            loadError = "Couldn't read vCard"
            return
        }
        contacts = VCFParser.parse(text)
        if contacts.isEmpty { loadError = "No VCARD blocks found" }
    }
}

// MARK: - Models

private struct ParsedContact: Hashable {
    let fullName: String
    let organisation: String?
    let title: String?
    let phones: [TypedField]
    let emails: [TypedField]
    let addresses: [TypedField]
    let photo: Data?

    var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined()
    }
}

private struct TypedField: Hashable {
    let label: String
    let value: String
}

// MARK: - Parser

private enum VCFParser {

    static func parse(_ text: String) -> [ParsedContact] {
        // Line unfolding (RFC 6350 §3.2): leading WS continues the prior line.
        var unfolded: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if (raw.first == " " || raw.first == "\t"), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += String(raw.dropFirst())
            } else {
                unfolded.append(raw)
            }
        }

        var contacts: [ParsedContact] = []
        var inCard = false
        var current: [String: [(params: [String: String], value: String)]] = [:]

        for line in unfolded {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "BEGIN:VCARD" { inCard = true; current = [:]; continue }
            if t == "END:VCARD", inCard {
                contacts.append(buildContact(from: current))
                inCard = false
                continue
            }
            if !inCard { continue }

            guard let colon = t.firstIndex(of: ":") else { continue }
            var head = String(t[..<colon])
            let value = String(t[t.index(after: colon)...])
            var params: [String: String] = [:]
            if let semi = head.firstIndex(of: ";") {
                let pairs = head[head.index(after: semi)...].split(separator: ";")
                for p in pairs {
                    let kv = p.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 { params[String(kv[0]).uppercased()] = String(kv[1]) }
                    else if let kv1 = kv.first { params["TYPE", default: ""] += String(kv1) }
                }
                head = String(head[..<semi])
            }
            current[head.uppercased(), default: []].append((params, value))
        }

        return contacts
    }

    private static func buildContact(from raw: [String: [(params: [String: String], value: String)]]) -> ParsedContact {
        let fn = raw["FN"]?.first?.value ?? ""
        let org = raw["ORG"]?.first?.value
        let title = raw["TITLE"]?.first?.value

        var phones: [TypedField] = []
        for entry in raw["TEL"] ?? [] {
            let type = entry.params["TYPE"] ?? "VOICE"
            let label = type.split(separator: ",").first.map(String.init) ?? type
            phones.append(TypedField(label: VCardMappings.resolvePhoneType(label), value: entry.value))
        }

        var emails: [TypedField] = []
        for entry in raw["EMAIL"] ?? [] {
            let type = entry.params["TYPE"] ?? "OTHER"
            let label = type.split(separator: ",").first.map(String.init) ?? type
            emails.append(TypedField(label: VCardMappings.resolveEmailType(label), value: entry.value))
        }

        var addresses: [TypedField] = []
        for entry in raw["ADR"] ?? [] {
            let type = entry.params["TYPE"] ?? "HOME"
            let cleaned = entry.value
                .components(separatedBy: ";")
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            addresses.append(TypedField(label: VCardMappings.resolveAddressType(type), value: cleaned))
        }

        // PHOTO is base64-encoded inline (`PHOTO;ENCODING=b;TYPE=JPEG:...`).
        var photoData: Data?
        if let entry = raw["PHOTO"]?.first {
            photoData = Data(base64Encoded: entry.value, options: .ignoreUnknownCharacters)
        }

        return ParsedContact(
            fullName: fn, organisation: org, title: title,
            phones: phones, emails: emails, addresses: addresses,
            photo: photoData
        )
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
