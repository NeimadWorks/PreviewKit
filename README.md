# PreviewKit

> Format-agnostic file-preview and inspection module for macOS Swift apps.

PreviewKit is a SwiftUI-first preview system: a host supplies a `PreviewDataSource`,
PreviewKit dispatches to a renderer based on `ArtifactKind`. ~30 file types out of
the box, no external dependencies, MIT.

```
┌─ Host (Canopy / Cairn / yours) ───────────┐
│  PreviewDataSource                        │
│   ├─ rootItems: [PreviewItem]             │
│   ├─ data(for:) async throws -> Data      │
│   └─ temporaryURL(for:) async throws -> URL?
└────────────┬──────────────────────────────┘
             │
┌────────────▼──────────────────────────────┐
│  PreviewKit                               │
│   PreviewSplitView                        │
│   ┌───────────────┬───────────────────┐  │
│   │ Navigator     │ Renderer          │  │
│   │ (search +     │ (dispatched by    │  │
│   │  tree/flat)   │  ArtifactKind)    │  │
│   └───────────────┴───────────────────┘  │
└───────────────────────────────────────────┘
```

## Status

Active. Origin: extracted from [Cairn](https://github.com/NeimadWorks/Cairn) in
2026-04, where it shipped first. Now consumed by Cairn and
[Canopy](https://github.com/NeimadWorks/Canopy) as a shared module.

## Renderers

| Family | Kinds |
|--------|-------|
| Documents | PDF, Markdown, Office (DOCX/XLSX/PPTX), Pages/Numbers/Keynote, RTF, TXT |
| Images | JPEG, PNG, HEIC, WebP, TIFF, GIF, BMP, SVG, RAW (DNG/CR3/ARW/…) |
| Media | Video (MP4/MOV/MKV…), Audio (FLAC/MP3/WAV/…) with waveform |
| Source | Swift, JS/TS, Python, Rust, Go, C/C++, Ruby, Kotlin, Java, Shell, HTML, CSS |
| Data | JSON, YAML, TOML, XML, plist, CSV, TSV, SQLite |
| Archives | zip, tar, gz, 7z, rar |
| Specialised | .icns, .patch / .diff, .mobileprovision, .gpg / .sig / .asc, Mach-O |
| Fallback | hex dump for unrecognised binaries |

A single `ArtifactKind` enum + 17 renderers, dispatched via `RendererRegistry`.
Hosts can register custom renderers at higher priority to override built-ins.

## Quick start

```swift
import PreviewKit

// 1. Bootstrap the renderer registry once (typically in your App.init).
PreviewKit.bootstrap()

// 2. Implement PreviewDataSource for your storage.
final class MyDataSource: PreviewDataSource { /* … */ }

// 3. Mount the split view.
PreviewSplitView(dataSource: MyDataSource())
```

For a host that doesn't want the navigator, use the registry directly:

```swift
let renderer = RendererRegistry.shared.renderer(for: item.kind)
renderer.body(for: item, data: bytes, url: nil)
```

## Public surface

- `PreviewItem` — leaf or group descriptor
- `ArtifactKind` — type taxonomy (~30 cases)
- `PreviewDataSource` / `NavigatorDataSource` — host contracts
- `RendererProtocol` / `RendererRegistry` — pluggable renderer dispatch
- `PreviewSplitView` — navigator + renderer column
- `CairnMeta` — optional Cairn-specific metadata (compression ratio, codec, relations)
- Components: `KPITileRow`, `MIMEBar`, `CompressionRing`, `HexDumpView`,
  `WaveformView`, `SemanticBadge`, `StructureOutlineView`, `OverviewGrid`

## License

MIT.

PreviewKit is part of the Neimad toolchain. Sibling: [Pry](https://github.com/NeimadWorks/pry) (UI test runner).
