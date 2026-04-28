// Tests for OOXML parser helpers. Exercise each XMLParser visitor
// against canonical XML fragments — covers the DOCX text/paragraph/
// tracked-change tally, the comment count, the XLSX workbook + formula
// tally, and the PPTX presentation + layout visitors.

import XCTest
@testable import PreviewKit

final class OOXMLParserTests: XCTestCase {

    // MARK: - OfficeKind

    func testOfficeKindFromExtension() {
        XCTAssertEqual(OfficeKind(extension: "docx"), .docx)
        XCTAssertEqual(OfficeKind(extension: "docm"), .docx)
        XCTAssertEqual(OfficeKind(extension: "xlsx"), .xlsx)
        XCTAssertEqual(OfficeKind(extension: "xlsm"), .xlsx)
        XCTAssertEqual(OfficeKind(extension: "pptx"), .pptx)
        XCTAssertEqual(OfficeKind(extension: "pptm"), .pptx)
        XCTAssertEqual(OfficeKind(extension: "pages"), .unknown)
        XCTAssertEqual(OfficeKind(extension: ""),      .unknown)
    }

    func testMacroDetection() {
        XCTAssertTrue(OfficeKind.macros(extension: "docm"))
        XCTAssertTrue(OfficeKind.macros(extension: "xlsm"))
        XCTAssertTrue(OfficeKind.macros(extension: "pptm"))
        XCTAssertFalse(OfficeKind.macros(extension: "docx"))
        XCTAssertFalse(OfficeKind.macros(extension: "pages"))
    }

    func testOfficeKindDisplayLabels() {
        XCTAssertEqual(OfficeKind.docx.displayLabel, "Word")
        XCTAssertEqual(OfficeKind.xlsx.displayLabel, "Excel")
        XCTAssertEqual(OfficeKind.pptx.displayLabel, "PowerPoint")
    }

    // MARK: - DOCX visitor

    func testDocxTextVisitorCountsWordsAndParagraphs() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="urn:ns">
          <w:body>
            <w:p><w:r><w:t>Hello world</w:t></w:r></w:p>
            <w:p><w:r><w:t>second paragraph goes here</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let stats = try DocxTextVisitor.visit(xml: Data(xml.utf8))
        XCTAssertEqual(stats.paragraphs, 2)
        XCTAssertEqual(stats.words, 6) // hello, world, second, paragraph, goes, here
        XCTAssertEqual(stats.trackedChanges, 0)
    }

    func testDocxTextVisitorCountsTrackedChanges() throws {
        let xml = """
        <w:document xmlns:w="urn:ns">
          <w:body>
            <w:p>
              <w:ins><w:r><w:t>added</w:t></w:r></w:ins>
              <w:del><w:r><w:t>removed</w:t></w:r></w:del>
            </w:p>
          </w:body>
        </w:document>
        """
        let stats = try DocxTextVisitor.visit(xml: Data(xml.utf8))
        XCTAssertEqual(stats.trackedChanges, 2)
    }

    func testCommentVisitorCountsComments() {
        let xml = """
        <w:comments xmlns:w="urn:ns">
          <w:comment w:id="1"><w:p/></w:comment>
          <w:comment w:id="2"><w:p/></w:comment>
          <w:comment w:id="3"><w:p/></w:comment>
        </w:comments>
        """
        XCTAssertEqual(CommentCountVisitor.visit(xml: Data(xml.utf8)), 3)
    }

    // MARK: - XLSX visitors

    func testXlsxWorkbookVisitorCountsSheetsAndNames() {
        let xml = """
        <workbook xmlns="ns">
          <sheets>
            <sheet name="Sales" sheetId="1"/>
            <sheet name="Costs" sheetId="2"/>
            <sheet name="Margin" sheetId="3"/>
          </sheets>
          <definedNames>
            <definedName name="Region">Sales!$A$1</definedName>
            <definedName name="Total">Costs!$B$2</definedName>
          </definedNames>
        </workbook>
        """
        let out = XlsxWorkbookVisitor.visit(xml: Data(xml.utf8))
        XCTAssertEqual(out.sheetCount, 3)
        XCTAssertEqual(out.namedRangeCount, 2)
    }

    func testXlsxFormulaVisitorCountsFormulaElements() {
        let xml = """
        <sheetData>
          <row>
            <c r="A1"><f>SUM(B1:B10)</f><v>45</v></c>
            <c r="A2"><f>B2*2</f><v>10</v></c>
            <c r="A3"><v>42</v></c>
          </row>
        </sheetData>
        """
        XCTAssertEqual(XlsxFormulaVisitor.visit(xml: Data(xml.utf8)), 2)
    }

    // MARK: - PPTX visitors

    func testPptxPresentationVisitorCountsSlides() {
        let xml = """
        <p:presentation xmlns:p="urn:ns">
          <p:sldIdLst>
            <p:sldId id="256" r:id="rId1"/>
            <p:sldId id="257" r:id="rId2"/>
            <p:sldId id="258" r:id="rId3"/>
            <p:sldId id="259" r:id="rId4"/>
          </p:sldIdLst>
        </p:presentation>
        """
        XCTAssertEqual(PptxPresentationVisitor.visit(xml: Data(xml.utf8)).slideCount, 4)
    }

    func testPptxLayoutVisitorReadsContentTypes() {
        let xml = """
        <Types>
          <Override PartName="/ppt/slideLayouts/slideLayout1.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
          <Override PartName="/ppt/slideLayouts/slideLayout2.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
          <Override PartName="/ppt/slides/slide1.xml"
                    ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
        </Types>
        """
        XCTAssertEqual(PptxLayoutVisitor.visit(xml: Data(xml.utf8)), 2)
    }
}
