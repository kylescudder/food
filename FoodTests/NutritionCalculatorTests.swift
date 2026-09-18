import XCTest
@testable import Food

final class NutritionCalculatorTests: XCTestCase {
    func testCalculatesBatchAndPerServingNutritionFromVerifiedProfiles() {
        let result = NutritionCalculator.calculate(
            ingredients: [
                NutritionIngredient(
                    name: "Tofu",
                    amount: 275,
                    unit: "g",
                    basisQuantity: 100,
                    basisUnit: "g",
                    caloriesPerBasis: 145,
                    proteinPerBasis: 16
                ),
                NutritionIngredient(
                    name: "Houmous",
                    amount: 50,
                    unit: "g",
                    basisQuantity: 100,
                    basisUnit: "g",
                    caloriesPerBasis: 307,
                    proteinPerBasis: 6.8
                )
            ],
            servings: 2
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.batch.calories, 552.25, accuracy: 0.001)
        XCTAssertEqual(result.perServing.calories, 276.125, accuracy: 0.001)
        XCTAssertEqual(result.perServing.proteinGrams, 23.7, accuracy: 0.001)
    }

    func testConvertsKilogramsAndExplicitItemWeights() {
        let result = NutritionCalculator.calculate(
            ingredients: [
                NutritionIngredient(
                    name: "Potatoes",
                    amount: 0.5,
                    unit: "kg",
                    basisQuantity: 100,
                    basisUnit: "g",
                    caloriesPerBasis: 77,
                    proteinPerBasis: 2.2
                ),
                NutritionIngredient(
                    name: "Wraps",
                    amount: 2,
                    unit: "item",
                    basisQuantity: 100,
                    basisUnit: "g",
                    caloriesPerBasis: 285,
                    proteinPerBasis: 7.8,
                    gramsPerUnit: 70
                )
            ],
            servings: 2
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.batch.calories, 784, accuracy: 0.001)
        XCTAssertEqual(result.perServing.calories, 392, accuracy: 0.001)
    }

    func testUnknownConversionMakesNutritionIncompleteInsteadOfCountingZero() {
        let result = NutritionCalculator.calculate(
            ingredients: [
                NutritionIngredient(
                    name: "Vegan burger",
                    amount: 2,
                    unit: "item",
                    basisQuantity: 100,
                    basisUnit: "g",
                    caloriesPerBasis: 200,
                    proteinPerBasis: 15
                )
            ],
            servings: 2
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.unresolvedIngredients, ["Vegan burger"])
        XCTAssertEqual(result.batch, .zero)
    }
}
