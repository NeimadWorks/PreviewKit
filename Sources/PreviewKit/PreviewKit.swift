// PreviewKit — format-agnostic file-preview and inspection module.
//
// Public surface, re-exported for consumers. PreviewKit is designed to be
// extractable as a standalone Swift package; the only Cairn-specific type is
// `CairnMeta`, which is optional in every renderer. A host that doesn't need
// Cairn-specific metadata passes nil through the `cairnMetaProvider` closure.
//
// Session 1 foundation: protocols, models, registry, navigator, shared
// components, `BinaryRenderer` + `OverviewRenderer`, `PreviewSplitView`.
// Sessions 2–4 add per-format renderers (documents, code/data, media).

@_exported import SwiftUI
import Foundation

/// Module identity / version — surfaced by consumers for diagnostics.
public enum PreviewKit {
    /// Semantic version of the PreviewKit public surface. Bumps on any
    /// source-breaking change to a `public` symbol.
    public static let version = "0.2.0"

    /// Install the built-in renderer roster on the shared registry.
    /// Idempotent — safe to call from each host at init time. Hosts that
    /// want to register custom renderers should do so *after* this call
    /// so their entries sit above PreviewKit's at equal priority.
    @MainActor
    public static func bootstrap(registry: RendererRegistry = .shared) {
        // Fallback — must be registered first so later renderers can
        // override on overlapping kinds.
        registry.register(BinaryRenderer.self)
        registry.setFallback(BinaryRenderer.self)

        // Session 2 — documents.
        registry.register(PDFRenderer.self)
        registry.register(MarkdownRenderer.self)
        registry.register(OfficeRenderer.self)

        // Session 3 — code & data.
        registry.register(SourceCodeRenderer.self)
        registry.register(DataRenderer.self)
        registry.register(FontRenderer.self)

        // Session 4 — visual media.
        registry.register(ImageRenderer.self)
        registry.register(RAWRenderer.self)
        registry.register(MediaRenderer.self)
        registry.register(ArchiveRenderer.self)
        // Session 5 polish-layer hooks register here.

        // Addendum v2 — specialised format renderers (v1.0 tier, batch 1).
        registry.register(PatchRenderer.self)
        registry.register(IconRenderer.self)
        registry.register(MobileProvisionRenderer.self)
        registry.register(GPGRenderer.self)

        // Addendum v3 — inherited from Canopy on extraction (2026-04).
        // SQLite gets a real renderer (Canopy had app-fingerprinting via
        // AppSignatureRegistry — Cairn's DataRenderer only listed it).
        // Calendar / Contact / WebShortcut / AppBundle are net-new types.
        registry.register(SQLiteRenderer.self)
        registry.register(CalendarRenderer.self)
        registry.register(ContactRenderer.self)
        registry.register(WebShortcutRenderer.self)
        registry.register(AppBundleRenderer.self)
    }
}
