// MobileProvisionRenderer — `.mobileprovision`, `.provisionprofile`.
//
// Developer-oriented inspector for Apple provisioning profiles. Surfaces
// the stuff that actually matters: days-until-expiry (color-coded),
// profile type, team, bundle id, entitlements list (dangerous ones in
// amber), and provisioned devices.

import SwiftUI

public struct MobileProvisionRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.mobileProvision] }
    public static var priority: Int { 0 }
    public static func make() -> MobileProvisionRenderer { MobileProvisionRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(MobileProvisionRendererBody(item: item, data: data, url: url))
    }
}

private struct MobileProvisionRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    private static let dangerousEntitlementPrefixes = [
        "com.apple.security.get-task-allow",
        "com.apple.private."
    ]

    private var profile: ProvisionProfile? {
        guard let data else { return nil }
        return MobileProvisionAnalyzer.parse(data: data)
    }

    var body: some View {
        HSplitView {
            renderPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
    }

    // MARK: - Left

    private var renderPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                profileCard
                if let p = profile, !p.entitlements.isEmpty {
                    entitlementsCard(p)
                }
                if let p = profile, !p.provisionedDevices.isEmpty {
                    devicesCard(p)
                }
            }
            .padding(18)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var profileCard: some View {
        if let p = profile {
            VStack(alignment: .leading, spacing: 10) {
                Text("PROVISIONING PROFILE")
                    .font(PreviewTokens.fontLabel)
                    .tracking(PreviewTokens.labelLetterSpacing)
                    .foregroundStyle(PreviewTokens.accentOrange)
                Text(p.name)
                    .font(PreviewTokens.fontHeader)
                Text(typeLabel(p.profileType))
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
                Divider().opacity(0.3)
                expiryRow(for: p)
                row("Team",   "\(p.teamName) (\(p.teamIdentifier))")
                row("Bundle", p.bundleIdentifier)
                if !p.uuid.isEmpty { row("UUID", p.uuid) }
            }
            .padding(PreviewTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .fill(PreviewTokens.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .strokeBorder(expiryColor(for: p).opacity(0.3),
                                  lineWidth: PreviewTokens.borderWidth)
            )
        } else {
            ContentUnavailableMessage(
                title: "Could not parse profile",
                subtitle: "The embedded plist could not be extracted from this provisioning profile.",
                symbol: "exclamationmark.triangle"
            )
        }
    }

    private func expiryRow(for p: ProvisionProfile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(expiryColor(for: p))
                .frame(width: 8, height: 8)
            if let days = p.daysUntilExpiry {
                if days >= 0 {
                    Text("Expires in \(days) days")
                        .font(PreviewTokens.fontMonoLarge)
                        .foregroundStyle(expiryColor(for: p))
                } else {
                    Text("Expired \(-days) days ago")
                        .font(PreviewTokens.fontMonoLarge)
                        .foregroundStyle(PreviewTokens.semanticText(.danger))
                }
            } else {
                Text("Expiration unknown")
                    .font(PreviewTokens.fontMonoLarge)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
            if let exp = p.expirationDate {
                Text("· \(formatDate(exp))")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
    }

    private func entitlementsCard(_ p: ProvisionProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENTITLEMENTS")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            ForEach(Array(p.entitlements.enumerated()), id: \.offset) { _, e in
                HStack(alignment: .firstTextBaseline) {
                    Text(e.key)
                        .font(PreviewTokens.fontMonoLarge)
                        .foregroundStyle(isDangerous(e.key)
                            ? PreviewTokens.semanticText(.warning)
                            : PreviewTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(e.value)
                        .font(PreviewTokens.fontMonoLarge)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    private func devicesCard(_ p: ProvisionProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROVISIONED DEVICES (\(p.provisionedDevices.count))")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            ForEach(p.provisionedDevices.prefix(30), id: \.self) { udid in
                Text(udid)
                    .font(PreviewTokens.fontMonoLarge)
                    .foregroundStyle(PreviewTokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if p.provisionedDevices.count > 30 {
                Text("+ \(p.provisionedDevices.count - 30) more")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
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
        guard let p = profile else { return [] }
        let days = p.daysUntilExpiry.map(String.init) ?? "—"
        return [
            KPITile(value: days, label: "Days left",
                    badge: expiryBadge(for: p)),
            KPITile(value: "\(p.provisionedDevices.count)", label: "Devices"),
            KPITile(value: "\(p.entitlements.count)", label: "Entitlements"),
            KPITile(value: typeLabel(p.profileType), label: "Type"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let p = profile else { return [] }
        var out: [SemanticBadgeModel] = []
        let dangerous = p.entitlements.filter { isDangerous($0.key) }
        if !dangerous.isEmpty {
            out.append(.init(
                text: "Dangerous entitlements: \(dangerous.count)",
                style: .warning, icon: "exclamationmark.shield"
            ))
        }
        if let days = p.daysUntilExpiry, days < 14 {
            out.append(.init(
                text: days < 0 ? "Expired" : "Expiring soon",
                style: .danger, icon: "calendar.badge.exclamationmark"
            ))
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
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(PreviewTokens.fontMonoLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func typeLabel(_ t: ProvisionProfile.ProfileType) -> String {
        switch t {
        case .appStore:    return "App Store"
        case .adHoc:       return "Ad Hoc"
        case .development: return "Development"
        case .enterprise:  return "Enterprise"
        case .unknown:     return "Unknown"
        }
    }

    private func expiryColor(for p: ProvisionProfile) -> Color {
        guard let d = p.daysUntilExpiry else { return PreviewTokens.textMuted }
        if d < 14  { return PreviewTokens.semanticText(.danger) }
        if d < 60  { return PreviewTokens.semanticText(.warning) }
        return PreviewTokens.semanticText(.success)
    }

    private func expiryBadge(for p: ProvisionProfile) -> BadgeStyle? {
        guard let d = p.daysUntilExpiry else { return nil }
        if d < 14  { return .danger }
        if d < 60  { return .warning }
        return .success
    }

    private func isDangerous(_ key: String) -> Bool {
        Self.dangerousEntitlementPrefixes.contains { key.hasPrefix($0) }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}
