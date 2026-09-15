import Foundation

struct PlannedIngredient: Equatable {
    let name: String
    let amount: Double?
    let unit: String?
    let categoryName: String
    let isPantryStaple: Bool
}

struct AggregatedIngredient: Identifiable, Equatable {
    let id: String
    let name: String
    var amount: Double?
    let unit: String?
    let categoryName: String
    let isPantryStaple: Bool
}

enum ShoppingListAggregator {
    static func aggregate(_ ingredients: [PlannedIngredient]) -> [AggregatedIngredient] {
        var results: [String: AggregatedIngredient] = [:]

        for ingredient in ingredients {
            let nameKey = normalize(ingredient.name)
            let unitKey = normalize(ingredient.unit ?? "")
            let key = "\(nameKey)|\(unitKey)"

            if var existing = results[key] {
                switch (existing.amount, ingredient.amount) {
                case let (.some(lhs), .some(rhs)):
                    existing.amount = lhs + rhs
                case (.none, .none):
                    break
                default:
                    // A known quantity must not be silently merged into an unquantified item.
                    let alternateKey = "\(key)|\(ingredient.amount == nil ? "unquantified" : "quantified")"
                    if var alternate = results[alternateKey],
                       let lhs = alternate.amount, let rhs = ingredient.amount {
                        alternate.amount = lhs + rhs
                        results[alternateKey] = alternate
                    } else {
                        results[alternateKey] = makeResult(ingredient, id: alternateKey)
                    }
                }
                results[key] = existing
            } else {
                results[key] = makeResult(ingredient, id: key)
            }
        }

        return results.values.sorted {
            let lhsCategory = ShoppingCategoryName.orderedName($0.categoryName)
            let rhsCategory = ShoppingCategoryName.orderedName($1.categoryName)
            return lhsCategory == rhsCategory
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : lhsCategory < rhsCategory
        }
    }

    static func ingredients(from entries: [MealPlanEntry]) -> [PlannedIngredient] {
        entries.flatMap { entry -> [PlannedIngredient] in
            guard !entry.isLeftover, let recipe = entry.recipe else { return [] }
            let denominator = max(recipe.defaultServings, 1)
            let scale = max(entry.plannedServings, 1) / denominator

            return recipe.sortedIngredients.map { ingredient in
                PlannedIngredient(
                    name: ingredient.name ?? "Ingredient",
                    amount: ingredient.hasAmount ? ingredient.amount * scale : nil,
                    unit: ingredient.unit,
                    categoryName: ingredient.categoryName ?? ShoppingCategoryName.cupboard.rawValue,
                    isPantryStaple: ingredient.isPantryStaple
                )
            }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func makeResult(_ ingredient: PlannedIngredient, id: String) -> AggregatedIngredient {
        AggregatedIngredient(
            id: id,
            name: ingredient.name.prefix(1).uppercased() + String(ingredient.name.dropFirst()),
            amount: ingredient.amount,
            unit: ingredient.unit,
            categoryName: ingredient.categoryName,
            isPantryStaple: ingredient.isPantryStaple
        )
    }
}
