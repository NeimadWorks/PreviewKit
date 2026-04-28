// sample.swift — PreviewKit SourceCode fixture
import Foundation

/// A typed identifier for things that can be previewed.
public struct PreviewID: Hashable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
}

public protocol Previewable {
    var id: PreviewID { get }
    func describe() -> String
}

public final class SamplePreview: Previewable {
    public let id: PreviewID
    public init(id: PreviewID) { self.id = id }
    public func describe() -> String { "sample(\(id.raw))" }
}

// TODO: cover edge cases
// FIXME: handle empty inputs

extension SamplePreview {
    public static let preset = SamplePreview(id: PreviewID("preset"))
}
