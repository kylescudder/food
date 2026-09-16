import XCTest
@testable import Food

final class RecipeServingScalerTests: XCTestCase {
    func testScalingRecipeFromTwoToThreeServings() {
        XCTAssertEqual(
            RecipeServingScaler.scaledAmount(275, from: 2, to: 3),
            412.5,
            accuracy: 0.001
        )
    }

    func testScalingDoesNotDivideByZero() {
        XCTAssertEqual(
            RecipeServingScaler.scaledAmount(40, from: 0, to: 2),
            80,
            accuracy: 0.001
        )
    }
}
