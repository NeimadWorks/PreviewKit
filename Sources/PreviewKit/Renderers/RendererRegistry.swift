// RendererRegistry — ArtifactKind → RendererProtocol dispatch.
//
// MainActor-isolated so lookups happen on the same actor as the view
// code that consumes them. Registration is idempotent — re-registering
// the same renderer type replaces the previous entry so hosts can hot-
// swap without leaking duplicates.

import SwiftUI

@MainActor
public final class RendererRegistry {

    public static let shared = RendererRegistry()

    /// Storage: one slot per registered renderer type. Lookup scans the
    /// whole slice — fine given the bounded renderer count (≤ 20) and
    /// avoids the per-kind multi-map book-keeping that would otherwise
    /// be needed when a renderer's `supportedKinds` overlap.
    private var entries: [AnyRenderer] = []

    /// Explicit fallback used when no renderer claims a kind. Set by
    /// `PreviewKit.bootstrap()`; callers can override via
    /// `setFallback(_:)`.
    private var fallbackMaker: (@MainActor () -> any RendererProtocol)?

    public init() {}

    /// Register a renderer. Any previous entry with the same type name is
    /// replaced — hosts can hot-swap for diagnostics. Thread-safety is
    /// provided by MainActor isolation, not a lock.
    public func register<R: RendererProtocol>(_ type: R.Type) {
        let name = String(describing: R.self)
        entries.removeAll { $0.typeName == name }
        entries.append(AnyRenderer(type))
    }

    /// Drop every renderer. Used by tests so the shared registry can't
    /// leak state between cases.
    public func reset() {
        entries.removeAll()
        fallbackMaker = nil
    }

    /// Set the fallback renderer used when no entry claims a kind.
    public func setFallback<R: RendererProtocol>(_ type: R.Type) {
        fallbackMaker = { R.make() }
    }

    /// Snapshot of the currently registered renderers, for diagnostics.
    public var registered: [AnyRenderer] { entries }

    /// Resolve a renderer for an artifact kind. Matches the highest-
    /// priority registered entry that claims the kind; falls back to
    /// `fallbackMaker` when nothing matches. Traps when both lookups
    /// fail — misconfiguration that must be caught in CI, not in prod.
    public func renderer(for kind: ArtifactKind) -> any RendererProtocol {
        let candidates = entries.filter { $0.supportedKinds.contains(kind) }
        if let best = candidates.max(by: { $0.priority < $1.priority }) {
            return best.make()
        }
        if let maker = fallbackMaker {
            return maker()
        }
        preconditionFailure(
            "RendererRegistry has no renderer for \(kind) and no fallback set. " +
            "Call PreviewKit.bootstrap() before rendering."
        )
    }
}
