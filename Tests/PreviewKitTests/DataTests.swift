// Tests for DataRenderer helpers: JSON tree parse, CSV parse, type
// inference, header detection. All pure Swift.

import XCTest
@testable import PreviewKit

final class DataTests: XCTestCase {

    // MARK: - JSON

    func testJSONParseValidObject() {
        let json = #"{"name":"Cairn","ver":1.2,"list":[1,2,3]}"#
        let result = JSONTreeParser.parse(data: Data(json.utf8))
        XCTAssertTrue(result.isValid)
        guard case .object(let kvs) = result.root else {
            return XCTFail("root should be object")
        }
        XCTAssertEqual(kvs.count, 3)
    }

    func testJSONParseInvalidReportsErrorAndLine() {
        let bad = "{ name: \"missing quote }"
        let result = JSONTreeParser.parse(data: Data(bad.utf8))
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.error)
    }

    func testJSONTreeDepth() {
        let deep = #"{"a":{"b":{"c":{"d":1}}}}"#
        let result = JSONTreeParser.parse(data: Data(deep.utf8))
        XCTAssertEqual(result.root?.depth, 4)
    }

    func testJSONTreeKeyCount() {
        let src = #"{"a":1,"b":2,"c":3}"#
        let result = JSONTreeParser.parse(data: Data(src.utf8))
        XCTAssertEqual(result.root?.keyCount, 3)
    }

    func testJSONNodeIsContainer() {
        XCTAssertTrue(JSONTreeNode.array([]).isContainer)
        XCTAssertTrue(JSONTreeNode.object([]).isContainer)
        XCTAssertFalse(JSONTreeNode.string("x").isContainer)
        XCTAssertFalse(JSONTreeNode.number(1).isContainer)
        XCTAssertFalse(JSONTreeNode.bool(true).isContainer)
        XCTAssertFalse(JSONTreeNode.null.isContainer)
    }

    // MARK: - Plist

    func testPlistRoundTripThroughBridge() throws {
        let dict: [String: Any] = ["name": "Cairn", "version": 1]
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
        let result = PlistTreeParser.parse(data: data)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.root?.keyCount, 2)
    }

    // MARK: - CSV

    func testCSVParseSimple() {
        let src = "name,age\nAda,36\nBob,42"
        let rows = CSVInspector.parse(source: src, separator: ",")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["name", "age"])
        XCTAssertEqual(rows[1], ["Ada", "36"])
    }

    func testCSVParseQuotedFieldsWithCommas() {
        let src = #"name,note"# + "\n" + #""Grace","hello, world""#
        let rows = CSVInspector.parse(source: src, separator: ",")
        XCTAssertEqual(rows[1][1], "hello, world")
    }

    func testCSVParseEscapedQuotes() {
        let src = #"name,note"# + "\n" + #"Grace,"she said ""hi""""#
        let rows = CSVInspector.parse(source: src, separator: ",")
        XCTAssertEqual(rows[1][1], "she said \"hi\"")
    }

    func testCSVDetectHeaderWhenRow0IsAlphaAndRow1IsNumeric() {
        let rows = [["name", "age"], ["Ada", "36"]]
        XCTAssertTrue(CSVInspector.detectHeader(rows))
    }

    func testCSVHeaderFalseWhenRow0IsAlsoNumeric() {
        let rows = [["1", "2"], ["3", "4"]]
        XCTAssertFalse(CSVInspector.detectHeader(rows))
    }

    func testCSVTypeInferenceIntegerAndFloat() {
        let dataRows = [["1", "1.5"], ["2", "2.5"], ["3", "3.5"]]
        let types = CSVInspector.inferTypes(dataRows: dataRows, columnCount: 2)
        XCTAssertEqual(types, [.integer, .float])
    }

    func testCSVTypeInferenceEmpty() {
        let dataRows = [["", ""], ["", ""]]
        let types = CSVInspector.inferTypes(dataRows: dataRows, columnCount: 2)
        XCTAssertEqual(types, [.empty, .empty])
    }

    func testCSVInspectFullPipeline() {
        let src = "name,age\nAda,36\nBob,42\nCarol,29"
        let summary = CSVInspector.inspect(source: src, separator: ",")
        XCTAssertTrue(summary.hasHeader)
        XCTAssertEqual(summary.rowCount, 4)
        XCTAssertEqual(summary.columnCount, 2)
        XCTAssertEqual(summary.columnTypes, [.string, .integer])
    }

    // MARK: - TSV

    func testTSVParse() {
        let src = "a\tb\nc\td"
        let rows = CSVInspector.parse(source: src, separator: "\t")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], ["c", "d"])
    }
}
