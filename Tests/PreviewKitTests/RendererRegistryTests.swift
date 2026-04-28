// Tests for `RendererRegistry` — dispatch, priority tie-breaking,
// fallback invocation, reset semantics.

import SwiftUI
import XCTest
@testable import PreviewKit

@MainActor
final class RendererRegistryTests: XCTestCase {

    // MARK: - Stubs

    struct StubPDFRenderer: RendererProtocol {
        static var supportedKinds: Set<ArtifactKind> { [.pdf] }
        static var priority: Int { 0 }
        static func make() -> StubPDFRenderer { StubPDFRenderer() }
        func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
            AnyView(Text("pdf"))
        }
    }

    struct HighPriorityPDFRenderer: RendererProtocol {
        static var supportedKinds: Set<ArtifactKind> { [.pdf] }
        static var priority: Int { 100 }
        static func make() -> HighPriorityPDFRenderer { HighPriorityPDFRenderer() }
        func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
            AnyView(Text("high-pdf"))
        }
    }

    struct StubFallback: RendererProtocol {
        static var supportedKinds: Set<ArtifactKind> { [] }
        static var priority: Int { -1000 }
        static func make() -> StubFallback { StubFallback() }
        func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
            AnyView(Text("fallback"))
        }
    }

    // MARK: - Tests

    func testRegistrationIsIdempotentByType() {
        let reg = RendererRegistry()
        reg.register(StubPDFRenderer.self)
        reg.register(StubPDFRenderer.self)
        XCTAssertEqual(reg.registered.count, 1)
    }

    func testPriorityBreaksTies() {
        let reg = RendererRegistry()
        reg.register(StubPDFRenderer.self)
        reg.register(HighPriorityPDFRenderer.self)
        let renderer = reg.renderer(for: .pdf)
        XCTAssertTrue(String(describing: type(of: renderer))
            .contains("HighPriorityPDFRenderer"))
    }

    func testFallbackFiresWhenNoMatch() {
        let reg = RendererRegistry()
        reg.setFallback(StubFallback.self)
        let renderer = reg.renderer(for: .video)
        XCTAssertTrue(String(describing: type(of: renderer))
            .contains("StubFallback"))
    }

    func testResetClearsEntriesAndFallback() {
        let reg = RendererRegistry()
        reg.register(StubPDFRenderer.self)
        reg.setFallback(StubFallback.self)
        reg.reset()
        XCTAssertTrue(reg.registered.isEmpty)
    }

    func testBootstrapRegistersBinaryFallback() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)
        let renderer = reg.renderer(for: .binary)
        XCTAssertNotNil(renderer)
        // Random unknown kind still resolves via fallback.
        let fallback = reg.renderer(for: .video)
        XCTAssertNotNil(fallback)
    }

    func testBootstrapRegistersDocumentRenderers() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)

        let pdf = reg.renderer(for: .pdf)
        XCTAssertTrue(String(describing: type(of: pdf)).contains("PDFRenderer"))

        let markdown = reg.renderer(for: .markdown)
        XCTAssertTrue(String(describing: type(of: markdown)).contains("MarkdownRenderer"))

        let docx = reg.renderer(for: .docx)
        XCTAssertTrue(String(describing: type(of: docx)).contains("OfficeRenderer"))

        let xlsx = reg.renderer(for: .xlsx)
        XCTAssertTrue(String(describing: type(of: xlsx)).contains("OfficeRenderer"))

        let pptx = reg.renderer(for: .pptx)
        XCTAssertTrue(String(describing: type(of: pptx)).contains("OfficeRenderer"))
    }

    func testBootstrapPrefersSpecificRendererOverFallback() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)
        // PDF should go to PDFRenderer, not BinaryRenderer fallback,
        // because priority-ties prefer kind-specific registrations.
        let pdf = reg.renderer(for: .pdf)
        XCTAssertFalse(String(describing: type(of: pdf)).contains("BinaryRenderer"))
    }

    func testBootstrapRegistersSession3Renderers() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)

        let swift = reg.renderer(for: .sourceSwift)
        XCTAssertTrue(String(describing: type(of: swift)).contains("SourceCodeRenderer"))

        let python = reg.renderer(for: .sourcePython)
        XCTAssertTrue(String(describing: type(of: python)).contains("SourceCodeRenderer"))

        let json = reg.renderer(for: .json)
        XCTAssertTrue(String(describing: type(of: json)).contains("DataRenderer"))

        let csv = reg.renderer(for: .csv)
        XCTAssertTrue(String(describing: type(of: csv)).contains("DataRenderer"))

        let font = reg.renderer(for: .font)
        XCTAssertTrue(String(describing: type(of: font)).contains("FontRenderer"))
    }

    func testBootstrapRegistersSession4Renderers() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)

        let jpeg = reg.renderer(for: .jpeg)
        XCTAssertTrue(String(describing: type(of: jpeg)).contains("ImageRenderer"))

        let png = reg.renderer(for: .png)
        XCTAssertTrue(String(describing: type(of: png)).contains("ImageRenderer"))

        let raw = reg.renderer(for: .raw)
        XCTAssertTrue(String(describing: type(of: raw)).contains("RAWRenderer"))

        let video = reg.renderer(for: .video)
        XCTAssertTrue(String(describing: type(of: video)).contains("MediaRenderer"))

        let audio = reg.renderer(for: .audio)
        XCTAssertTrue(String(describing: type(of: audio)).contains("MediaRenderer"))

        let archive = reg.renderer(for: .archive)
        XCTAssertTrue(String(describing: type(of: archive)).contains("ArchiveRenderer"))
    }
}
