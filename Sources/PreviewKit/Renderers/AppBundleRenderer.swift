// AppBundleRenderer — introspects a `.app` directory via NSBundle and
// surfaces the icon, version, supported architectures, sandbox/Hardened-
// Runtime flags, code signature, and minimum macOS version.
//
// Origin: Canopy's `AppInspectorHero`, merged on extraction.

import SwiftUI
import AppKit

public struct AppBundleRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.appBundle] }
    public static var priority: Int { 0 }
    public static func make() -> AppBundleRenderer { AppBundleRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(AppBundleRendererBody(item: item, data: data, url: url))
    }
}

private struct AppBundleRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var info: BundleInfo?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let info {
                    header(info)
                    KPITileRow(kpiTiles(info), columns: 4)
                    if !badges(info).isEmpty {
                        SemanticBadgeRow(badges(info))
                    }
                    if !info.frameworks.isEmpty {
                        frameworksList(info.frameworks)
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

    @ViewBuilder
    private func header(_ info: BundleInfo) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon = info.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(PreviewTokens.mimeColor(for: .system))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(info.displayName).font(PreviewTokens.fontHeader)
                if let bundleID = info.bundleIdentifier {
                    Text(bundleID)
                        .font(PreviewTokens.fontLabel.monospaced())
                        .foregroundStyle(PreviewTokens.textMuted)
                }
                if let copyright = info.copyright {
                    Text(copyright)
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                }
            }
            Spacer()
        }
    }

    private func kpiTiles(_ info: BundleInfo) -> [KPITile] {
        var tiles: [KPITile] = []
        if let v = info.shortVersion {
            tiles.append(KPITile(value: v, label: "Version"))
        }
        if let build = info.buildNumber {
            tiles.append(KPITile(value: build, label: "Build"))
        }
        if let min = info.minimumOSVersion {
            tiles.append(KPITile(value: min, label: "min macOS"))
        }
        if let arch = info.architectures, !arch.isEmpty {
            tiles.append(KPITile(value: arch.joined(separator: " · "), label: "Arch"))
        }
        if let size = info.totalSizeBytes {
            tiles.append(KPITile(
                value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                label: "Size"
            ))
        }
        return tiles
    }

    private func badges(_ info: BundleInfo) -> [SemanticBadgeModel] {
        var b: [SemanticBadgeModel] = []
        if info.isSandboxed {
            b.append(SemanticBadgeModel(text: "Sandboxed", style: .success, icon: "shield"))
        }
        if info.isHardenedRuntime {
            b.append(SemanticBadgeModel(text: "Hardened", style: .success))
        }
        if info.hasNotarization == true {
            b.append(SemanticBadgeModel(text: "Notarized", style: .success, icon: "checkmark.seal"))
        }
        if let arch = info.architectures, arch.contains("arm64") && arch.contains("x86_64") {
            b.append(SemanticBadgeModel(text: "Universal", style: .info))
        }
        return b
    }

    private func frameworksList(_ frameworks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frameworks")
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
                .textCase(.uppercase)
            ForEach(frameworks.prefix(8), id: \.self) { fw in
                Text(fw)
                    .font(PreviewTokens.fontLabel.monospaced())
                    .foregroundStyle(PreviewTokens.textMuted)
            }
            if frameworks.count > 8 {
                Text("+\(frameworks.count - 8) more")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        // .app bundles are directories — must come from a URL.
        guard let url else {
            loadError = "App bundles need a file URL"
            return
        }
        let bundle = Bundle(url: url)
        guard let bundle else {
            loadError = "Couldn't open bundle"
            return
        }

        let plist = bundle.infoDictionary ?? [:]
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        // Icon
        var icon: NSImage?
        if let iconName = plist["CFBundleIconFile"] as? String {
            let trimmed = iconName.replacingOccurrences(of: ".icns", with: "")
            icon = bundle.image(forResource: trimmed)
        }
        if icon == nil {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }

        // Architectures (from the executable's mach-o)
        let archs = readArchitectures(at: bundle.executableURL)

        // Frameworks under Contents/Frameworks
        let frameworksURL = url.appendingPathComponent("Contents/Frameworks")
        let frameworks = (try? FileManager.default.contentsOfDirectory(at: frameworksURL,
                                                                       includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "framework" }
            .map { $0.lastPathComponent }
            .sorted()
            ?? []

        // Total size
        let size = directorySize(at: url)

        info = BundleInfo(
            displayName: displayName,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            shortVersion: plist["CFBundleShortVersionString"] as? String,
            buildNumber: plist["CFBundleVersion"] as? String,
            minimumOSVersion: plist["LSMinimumSystemVersion"] as? String,
            copyright: plist["NSHumanReadableCopyright"] as? String,
            architectures: archs,
            isSandboxed: detectSandboxed(executableURL: bundle.executableURL),
            isHardenedRuntime: detectHardenedRuntime(executableURL: bundle.executableURL),
            hasNotarization: nil,   // requires `spctl` — too slow for inline render
            frameworks: frameworks,
            icon: icon,
            totalSizeBytes: size
        )
    }

    private func readArchitectures(at execURL: URL?) -> [String]? {
        guard let execURL,
              let data = try? Data(contentsOf: execURL, options: .alwaysMapped),
              data.count >= 8 else { return nil }
        let m = data.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Fat binary: header + nfat_arch * 20 bytes (cputype, cpusubtype, …)
        if m == 0xCAFEBABE || m == 0xBEBAFECA {
            let nfatBE = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            let nfat = m == 0xCAFEBABE ? UInt32(bigEndian: nfatBE) : nfatBE
            var archs: [String] = []
            for i in 0..<Int(nfat) {
                let off = 8 + i * 20
                guard data.count >= off + 4 else { break }
                let cputypeBE = data.withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt32.self) }
                let cputype = m == 0xCAFEBABE ? UInt32(bigEndian: cputypeBE) : cputypeBE
                if let label = cpuTypeLabel(cputype) { archs.append(label) }
            }
            return archs
        }
        // Thin Mach-O
        if m == 0xFEEDFACE || m == 0xCEFAEDFE {
            return ["i386"]   // 32-bit BE/LE
        }
        if m == 0xFEEDFACF || m == 0xCFFAEDFE {
            let cputypeBE = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            let cputype = m == 0xFEEDFACF ? UInt32(bigEndian: cputypeBE) : cputypeBE
            return [cpuTypeLabel(cputype) ?? "unknown"]
        }
        return nil
    }

    private func cpuTypeLabel(_ cputype: UInt32) -> String? {
        switch cputype & 0x00ffffff {
        case 0x07: return "x86_64"
        case 0x0c: return "arm64"
        default:   return nil
        }
    }

    private func detectSandboxed(executableURL: URL?) -> Bool {
        guard let executableURL,
              let data = try? Data(contentsOf: executableURL, options: .alwaysMapped) else { return false }
        // Heuristic: presence of "com.apple.security.app-sandbox" string in the binary.
        return data.range(of: Data("com.apple.security.app-sandbox".utf8)) != nil
    }

    private func detectHardenedRuntime(executableURL: URL?) -> Bool {
        guard let executableURL,
              let data = try? Data(contentsOf: executableURL, options: .alwaysMapped) else { return false }
        return data.range(of: Data("LIBRARY_VALIDATION".utf8)) != nil
    }

    private func directorySize(at url: URL) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(v?.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - Models

private struct BundleInfo: Hashable {
    let displayName: String
    let bundleIdentifier: String?
    let shortVersion: String?
    let buildNumber: String?
    let minimumOSVersion: String?
    let copyright: String?
    let architectures: [String]?
    let isSandboxed: Bool
    let isHardenedRuntime: Bool
    let hasNotarization: Bool?
    let frameworks: [String]
    let icon: NSImage?
    let totalSizeBytes: Int64?
}
