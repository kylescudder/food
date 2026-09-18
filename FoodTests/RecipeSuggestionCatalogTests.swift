import XCTest
@testable import Food

final class RecipeSuggestionCatalogTests: XCTestCase {
    func testFallbackSuggestionsHaveCompleteCalculatedNutrition() {
        let suggestions = RecipeSuggestionCatalog.suggestions

        XCTAssertGreaterThanOrEqual(suggestions.count, 6)
        for suggestion in suggestions {
            let nutrition = suggestion.nutrition
            XCTAssertTrue(nutrition.isComplete, suggestion.name)
            XCTAssertGreaterThanOrEqual(nutrition.perServing.calories, 350, suggestion.name)
            XCTAssertLessThanOrEqual(nutrition.perServing.calories, 750, suggestion.name)
            XCTAssertGreaterThan(nutrition.perServing.proteinGrams, 15, suggestion.name)
        }
        XCTAssertGreaterThanOrEqual(
            suggestions.filter { $0.isBatchCook && $0.defaultServings >= 4 }.count,
            2
        )
    }

    func testSmokyTofuLentilPastaUsesWholeBatchThenDividesByTwo() throws {
        let recipe = try XCTUnwrap(RecipeSuggestionCatalog.suggestions.first {
            $0.name == "Smoky Tofu Lentil Pasta"
        })

        XCTAssertEqual(recipe.nutrition.batch.calories, 2_258.4, accuracy: 0.01)
        XCTAssertEqual(recipe.nutrition.perServing.calories, 564.6, accuracy: 0.01)
        XCTAssertEqual(recipe.nutrition.perServing.proteinGrams, 35.46, accuracy: 0.01)
    }
}
