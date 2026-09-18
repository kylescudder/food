import Foundation

struct NutritionFacts: Equatable, Sendable {
    var calories: Double
    var proteinGrams: Double

    static let zero = NutritionFacts(calories: 0, proteinGrams: 0)
}

struct NutritionIngredient: Equatable, Sendable {
    let name: String
    let amount: Double?
    let unit: String?
    let basisQuantity: Double
    let basisUnit: String
    let caloriesPerBasis: Double
    let proteinPerBasis: Double
    var gramsPerUnit: Double? = nil
    var millilitresPerUnit: Double? = nil
    var isExcluded: Bool = false
}

struct NutritionCalculation: Equatable, Sendable {
    let batch: NutritionFacts
    let perServing: NutritionFacts
    let unresolvedIngredients: [String]

    var isComplete: Bool { unresolvedIngredients.isEmpty }
}

enum NutritionCalculator {
    static func calculate(recipe: Recipe) -> NutritionCalculation {
        calculate(
            ingredients: recipe.sortedIngredients.map { ingredient in
                let profile = ingredient.nutritionProfile
                let amount: Double? = ingredient.hasNutritionAmount
                    ? ingredient.nutritionAmount
                    : (ingredient.hasAmount ? ingredient.amount : nil)
                return NutritionIngredient(
                    name: ingredient.name ?? "Ingredient",
                    amount: amount,
                    unit: ingredient.nutritionUnit ?? ingredient.unit,
                    basisQuantity: profile?.basisQuantity ?? 0,
                    basisUnit: profile?.basisUnit ?? "",
                    caloriesPerBasis: profile?.energyKcal ?? 0,
                    proteinPerBasis: profile?.proteinG ?? 0,
                    gramsPerUnit: ingredient.hasGramsPerUnit ? ingredient.gramsPerUnit : nil,
                    millilitresPerUnit: ingredient.hasMillilitresPerUnit
                        ? ingredient.millilitresPerUnit
                        : nil,
                    isExcluded: ingredient.excludeFromNutrition
                )
            },
            servings: recipe.defaultServings
        )
    }

    static func calculate(
        ingredients: [NutritionIngredient],
        servings: Double
    ) -> NutritionCalculation {
        var batch = NutritionFacts.zero
        var unresolved: [String] = []

        for ingredient in ingredients where !ingredient.isExcluded {
            guard let amount = ingredient.amount,
                  amount >= 0,
                  ingredient.basisQuantity > 0,
                  let amountInBasisUnit = convertedAmount(
                      amount,
                      unit: ingredient.unit,
                      basisUnit: ingredient.basisUnit,
                      gramsPerUnit: ingredient.gramsPerUnit,
                      millilitresPerUnit: ingredient.millilitresPerUnit
                  ) else {
                unresolved.append(ingredient.name)
                continue
            }

            let scale = amountInBasisUnit / ingredient.basisQuantity
            batch.calories += ingredient.caloriesPerBasis * scale
            batch.proteinGrams += ingredient.proteinPerBasis * scale
        }

        let divisor = max(servings, 1)
        return NutritionCalculation(
            batch: batch,
            perServing: NutritionFacts(
                calories: batch.calories / divisor,
                proteinGrams: batch.proteinGrams / divisor
            ),
            unresolvedIngredients: unresolved
        )
    }

    private static func normalized(_ unit: String?) -> String {
        (unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func convertedAmount(
        _ amount: Double,
        unit: String?,
        basisUnit: String,
        gramsPerUnit: Double?,
        millilitresPerUnit: Double?
    ) -> Double? {
        let source = normalized(unit)
        let destination = normalized(basisUnit)
        if source == destination { return amount }

        switch (source, destination) {
        case ("kg", "g"):
            return amount * 1_000
        case ("g", "kg"):
            return amount / 1_000
        case ("l", "ml"):
            return amount * 1_000
        case ("ml", "l"):
            return amount / 1_000
        case (_, "g") where isItemUnit(source):
            guard let gramsPerUnit, gramsPerUnit > 0 else { return nil }
            return amount * gramsPerUnit
        case (_, "ml") where isItemUnit(source):
            guard let millilitresPerUnit, millilitresPerUnit > 0 else { return nil }
            return amount * millilitresPerUnit
        default:
            return nil
        }
    }

    private static func isItemUnit(_ unit: String) -> Bool {
        ["", "item", "items", "portion", "portions", "slice", "slices", "tin", "tins"]
            .contains(unit)
    }
}
