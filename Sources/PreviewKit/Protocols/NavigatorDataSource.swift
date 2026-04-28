// NavigatorDataSource — read-only projection of PreviewDataSource the
// navigator depends on. Separating this from `PreviewDataSource` keeps the
// navigator layer decoupled from data loading: a test can drive the
// navigator with a stub that has no byte-reading responsibilities.

import Foundation

/// The navigator pulls its tree/flat list through this protocol. Every
/// real `PreviewDataSource` is also a `NavigatorDataSource` for free via
/// the default conformance below; custom tests can conform directly.
@MainActor
public protocol NavigatorDataSource: AnyObject {
    var rootItems: [PreviewItem] { get }
    var refreshToken: UUID { get }
}

extension StaticPreviewDataSource: NavigatorDataSource {}
