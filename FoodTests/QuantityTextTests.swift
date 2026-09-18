import XCTest
@testable import Food

final class QuantityTextTests: XCTestCase {
    func testParsesFormattedQuarterFractions() {
        XCTAssertEqual(QuantityText.parse("¼"), 0.25)
        XCTAssertEqual(QuantityText.parse("½"), 0.5)
        XCTAssertEqual(QuantityText.parse("¾"), 0.75)
        XCTAssertEqual(QuantityText.parse("1½"), 1.5)
    }

    func testParsesDecimalComma() {
        XCTAssertEqual(QuantityText.parse("0,5"), 0.5)
    }

    func testFormattedQuantityCanBeParsedWithoutDataLoss() throws {
        let formatted = QuantityText.format(0.75)
        let parsed = try XCTUnwrap(QuantityText.parse(formatted))

        XCTAssertEqual(parsed, 0.75)
    }
}
