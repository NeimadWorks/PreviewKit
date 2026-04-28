// RendererProtocol — one renderer per ArtifactKind family.
//
// Renderers are registered on `RendererRegistry.shared` at process start
// (PreviewKit installs its built-ins via `PreviewKit.bootstrap()`); hosts
// can register additional renderers to override built-ins or handle custom
// kinds. Dispatch is by `ArtifactKind` with `priority` breaking ties.
//
// Each renderer receives the item descriptor plus at most one of `data` or
// `url` populated by PreviewSplitView's loader. A renderer that needs a
// URL (QuickLook, AVPlayer) but only got `data` is responsible for writing
// a temp file itself.

import SwiftUI

/// A view-factory keyed by `ArtifactKind`. Renderers are value types or
/// small classes; the registry stores them by type, not instance, and
/// instantiates on demand via `make()`.
@MainActor
public protocol RendererProtocol {

    /// Kinds this renderer claims. A registry lookup asks each registered
    /// renderer whether it handles a kind; if multiple match, the highest
    /// `priority` wins.
    static var supportedKinds: Set<ArtifactKind> { get }

    /// Tie-breaker when multiple renderers claim the same kind. Default 0.
    /// Built-in renderers use 0; hosts can register overrides at priority
    /// 100+ to take precedence.
    static var priority: Int { get }

    /// Build a new renderer instance. The registry calls this on each
    /// lookup so renderers can carry per-invocation state (view-local
    /// caches, etc.) without worrying about stale shared state.
    static func make() -> Self

    /// The rendered view. Either `data` or `url` will be non-nil for leaf
    /// items, depending on the data source's `temporaryURL` implementation
    /// and the `inMemoryLimitBytes` cut-off.
    @ViewBuilder
    func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView
}

public extension RendererProtocol {
    static var priority: Int { 0 }
}

/// Type-erased renderer entry used inside the registry. Exposed as
/// `public` so hosts can enumerate the registered set (diagnostics,
/// debug commands).
@MainActor
public struct AnyRenderer {
    public let supportedKinds: Set<ArtifactKind>
    public let priority: Int
    public let typeName: String
    public let make: @MainActor () -> any RendererProtocol

    public init<R: RendererProtocol>(_ type: R.Type) {
        self.supportedKinds = R.supportedKinds
        self.priority       = R.priority
        self.typeName       = String(describing: R.self)
        self.make           = { R.make() }
    }
}
