// RAWRenderer — extends ImageRenderer's body with RAW-specific badges
// and a relation chip when a sidecar is detected.
//
// Implementation note: we reuse `ImageRendererBody` wholesale — the
// renderer protocol just routes different `ArtifactKind` values here.
// If RAW needs its own header / toolbar later we'll split; for now
// shared code pays its way.

import SwiftUI

public struct RAWRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.raw] }
    public static var priority: Int { 0 }
    public static func make() -> RAWRenderer { RAWRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(ImageRendererBody(item: item, data: data, url: url))
    }
}
