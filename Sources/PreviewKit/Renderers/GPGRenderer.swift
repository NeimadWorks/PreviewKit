// GPGRenderer — `.gpg`, `.asc`, `.sig`, `.pgp`.
//
// Never decrypts. Never verifies. Surfaces the armor metadata so a user
// who opens a signed-mail attachment in Cairn sees what they actually
// have without needing a terminal.

import SwiftUI

public struct GPGRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.gpgSignature, .gpgMessage] }
    public static var priority: Int { 0 }
    public static func make() -> GPGRenderer { GPGRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(GPGRendererBody(item: item, data: data, url: url))
    }
}

private struct GPGRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    private var specimen: GPGSpecimen {
        guard let data else {
            return GPGSpecimen(
                isArmored: false, blockType: .unknown,
                version: nil, comment: nil, hashAlgorithm: nil,
                bodyByteCount: 0, keyIDHex: nil
            )
        }
        return GPGAnalyzer.parse(data: data)
    }

    var body: some View {
        ResponsiveSplit {
            renderPane
        } inspector: {
            inspectorPane
        }
    }

    // MARK: - Left

    private var renderPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                card
                noteFooter
            }
            .padding(18)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var card: some View {
        let s = specimen
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName(for: s.blockType))
                    .font(.system(size: 20))
                    .foregroundStyle(PreviewTokens.accentOrange)
                Text(title(for: s.blockType))
                    .font(PreviewTokens.fontHeader)
                Spacer()
            }
            Divider().opacity(0.3)
            if let v = s.version { row("Version", v) }
            if let c = s.comment { row("Comment", c) }
            if let h = s.hashAlgorithm { row("Hash", h) }
            if let k = s.keyIDHex { row("Key ID", k) }
            row("Armored", s.isArmored ? "Yes (ASCII)" : "No (binary)")
            row("Body", "\(s.bodyByteCount) bytes")
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    private var noteFooter: some View {
        Text(footerNote(for: specimen.blockType))
            .font(PreviewTokens.fontBody)
            .foregroundStyle(PreviewTokens.textMuted)
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer()
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var kpis: [KPITile] {
        let s = specimen
        return [
            KPITile(value: title(for: s.blockType), label: "Type"),
            KPITile(value: s.isArmored ? "ASCII" : "Binary", label: "Encoding"),
            KPITile(value: s.keyIDHex ?? "—", label: "Key ID"),
            KPITile(value: "\(s.bodyByteCount)", label: "Body"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        switch specimen.blockType {
        case .signature, .signedMessage:
            out.append(.init(text: "Signature", style: .info, icon: "signature"))
        case .message:
            out.append(.init(text: "Encrypted", style: .warning, icon: "lock.fill"))
        case .publicKey:
            out.append(.init(text: "Public key", style: .info, icon: "key"))
        case .privateKey:
            out.append(.init(text: "PRIVATE KEY — do not share", style: .danger, icon: "key.fill"))
        case .unknown:
            out.append(.init(text: "Not armored", style: .neutral, icon: "questionmark.circle"))
        }
        if specimen.isArmored {
            out.append(.init(text: "ASCII armored", style: .neutral, icon: "textformat"))
        }
        return out
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(PreviewTokens.fontMonoLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func title(for t: GPGBlockType) -> String {
        switch t {
        case .message:       return "PGP ENCRYPTED MESSAGE"
        case .signature:     return "PGP SIGNATURE"
        case .publicKey:     return "PGP PUBLIC KEY"
        case .privateKey:    return "PGP PRIVATE KEY"
        case .signedMessage: return "PGP SIGNED MESSAGE"
        case .unknown:       return "OpenPGP data"
        }
    }

    private func iconName(for t: GPGBlockType) -> String {
        switch t {
        case .signature, .signedMessage: return "signature"
        case .message:                   return "lock.doc"
        case .publicKey:                 return "key"
        case .privateKey:                return "key.fill"
        case .unknown:                   return "lock.shield"
        }
    }

    private func footerNote(for t: GPGBlockType) -> String {
        switch t {
        case .signature, .signedMessage:
            return "Verification requires the signer's public key. Cairn does not verify signatures."
        case .message:
            return "Decryption requires your GPG private key. Cairn does not decrypt messages."
        case .publicKey:
            return "Import this key with gpg --import to use for verification."
        case .privateKey:
            return "Warning: private key blocks should be stored in a trusted keystore, not an archive shared with others."
        case .unknown:
            return "This file does not appear to be ASCII-armored. It may be a binary OpenPGP payload."
        }
    }
}
