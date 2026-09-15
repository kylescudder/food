import XCTest
@testable import ScudderMeals

final class ShoppingListAggregatorTests: XCTestCase {
    func testSameIngredientAndUnitCombines() {
        let result = ShoppingListAggregator.aggregate([
            PlannedIngredient(name: "Tofu", amount: 200, unit: "g", categoryName: "Fridge", isPantryStaple: false),
            PlannedIngredient(name: "tofu", amount: 275, unit: "g", categoryName: "Fridge", isPantryStaple: false)
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 475)
        XCTAssertEqual(result.first?.unit, "g")
    }

    func testIncompatibleUnitsStaySeparate() {
        let result = ShoppingListAggregator.aggregate([
            PlannedIngredient(name: "Soy milk", amount: 800, unit: "ml", categoryName: "Dairy", isPantryStaple: false),
            PlannedIngredient(name: "Soy milk", amount: 1, unit: "carton", categoryName: "Dairy", isPantryStaple: false)
        ])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.compactMap(\.unit)), Set(["ml", "carton"]))
    }

    func testUnquantifiedIngredientIsOnlyListedOnce() {
        let result = ShoppingListAggregator.aggregate([
            PlannedIngredient(name: "Lettuce", amount: nil, unit: nil, categoryName: "Fruit & Veg", isPantryStaple: false),
            PlannedIngredient(name: "lettuce", amount: nil, unit: nil, categoryName: "Fruit & Veg", isPantryStaple: false)
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.amount)
    }
}
