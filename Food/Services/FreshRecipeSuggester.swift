import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FreshRecipeSuggester {
    enum SuggestionError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "A new on-device suggestion isn’t available right now. The built-in fresh recipes still work offline."
            case .invalidResponse:
                "That suggestion wasn’t usable. Try again or use the proposed week."
            }
        }
    }

    static var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
#endif
        return false
    }

    static func suggestDinner(variation: Int) async throws -> RecipeSuggestionDraft {
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await FoundationModelRecipeSuggester.suggestDinner(variation: variation)
        }
#endif
        throw SuggestionError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedRecipeCopy {
    var name: String
    var description: String
    var steps: [String]
}

@available(iOS 26.0, *)
private enum FoundationModelRecipeSuggester {
    static func suggestDinner(variation: Int) async throws -> RecipeSuggestionDraft {
        guard SystemLanguageModel.default.isAvailable else {
            throw FreshRecipeSuggester.SuggestionError.unavailable
        }

        let dinnerTemplates = RecipeSuggestionCatalog.suggestions.filter { $0.mealType == .dinner }
        guard !dinnerTemplates.isEmpty else {
            throw FreshRecipeSuggester.SuggestionError.unavailable
        }
        let template = dinnerTemplates[abs(variation) % dinnerTemplates.count]
        let ingredientText = template.ingredients.map { ingredient in
            QuantityText.ingredient(
                amount: ingredient.amount,
                unit: ingredient.unit,
                name: ingredient.name,
                note: ingredient.note
            )
        }.joined(separator: ", ")

        let session = LanguageModelSession(instructions: """
        You create practical vegan meal ideas for a UK household of two. Be concise, familiar and easy to cook.
        The quantities and nutrition have already been calculated by the app. Never add, remove or change an ingredient.
        Pantry seasonings may be mentioned only when already listed. Return five to eight clear cooking steps.
        """)
        let response = try await session.respond(
            to: """
            Write a fresh name, one-sentence description and method for a dinner using exactly these ingredients:
            \(ingredientText)

            The recipe makes \(QuantityText.format(template.defaultServings)) servings. Keep that yield in the method.
            Avoid calling it \(template.name). Do not claim an exact calorie or protein value.
            """,
            generating: GeneratedRecipeCopy.self
        )
        let generated = response.content
        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = generated.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = generated.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !name.isEmpty, !description.isEmpty, (3...10).contains(steps.count) else {
            throw FreshRecipeSuggester.SuggestionError.invalidResponse
        }
        return template.replacingCopy(name: name, description: description, steps: steps)
    }
}
#endif
