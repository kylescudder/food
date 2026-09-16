import Foundation

enum RecipeServingScaler {
    static func scaledAmount(_ amount: Double, from baseServings: Double, to servings: Double) -> Double {
        amount * max(servings, 1) / max(baseServings, 1)
    }
}
