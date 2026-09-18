import CoreData
import Foundation

@objc(Household)
final class Household: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var seedVersion: Int16
    @NSManaged var kyleDailyCalorieTarget: Double
    @NSManaged var unplannedCalorieReserve: Double
    @NSManaged var recipes: NSSet?
    @NSManaged var mealPlanEntries: NSSet?
    @NSManaged var shoppingItems: NSSet?
    @NSManaged var categories: NSSet?
    @NSManaged var nutritionProfiles: NSSet?

    static func fetchRequest() -> NSFetchRequest<Household> {
        NSFetchRequest(entityName: "Household")
    }

    var hasCalorieTarget: Bool {
        primitiveValue(forKey: "kyleDailyCalorieTarget") != nil && kyleDailyCalorieTarget > 0
    }
}

@objc(Recipe)
final class Recipe: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var recipeDescription: String?
    @NSManaged var defaultServings: Double
    @NSManaged var caloriesPerServing: Double
    @NSManaged var proteinPerServing: Double
    @NSManaged var nutritionNote: String?
    @NSManaged var tags: String?
    @NSManaged var cookingRequired: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var isGenerated: Bool
    @NSManaged var isInRotation: Bool
    @NSManaged var household: Household?
    @NSManaged var ingredients: NSSet?
    @NSManaged var steps: NSSet?
    @NSManaged var mealPlanEntries: NSSet?

    static func fetchRequest() -> NSFetchRequest<Recipe> {
        NSFetchRequest(entityName: "Recipe")
    }

    var sortedIngredients: [RecipeIngredient] {
        (ingredients as? Set<RecipeIngredient> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedSteps: [RecipeStep] {
        (steps as? Set<RecipeStep> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var tagList: [String] {
        (tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var hasCalories: Bool { primitiveValue(forKey: "caloriesPerServing") != nil }
    var hasProtein: Bool { primitiveValue(forKey: "proteinPerServing") != nil }
}

@objc(RecipeIngredient)
final class RecipeIngredient: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var amount: Double
    @NSManaged var unit: String?
    @NSManaged var note: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var categoryName: String?
    @NSManaged var isPantryStaple: Bool
    @NSManaged var excludeFromNutrition: Bool
    @NSManaged var nutritionAmount: Double
    @NSManaged var nutritionUnit: String?
    @NSManaged var gramsPerUnit: Double
    @NSManaged var millilitresPerUnit: Double
    @NSManaged var recipe: Recipe?
    @NSManaged var nutritionProfile: FoodNutritionProfile?

    static func fetchRequest() -> NSFetchRequest<RecipeIngredient> {
        NSFetchRequest(entityName: "RecipeIngredient")
    }

    var hasAmount: Bool {
        entity.attributesByName["amount"]?.isOptional == false || primitiveValue(forKey: "amount") != nil
    }

    var hasNutritionAmount: Bool { primitiveValue(forKey: "nutritionAmount") != nil }
    var hasGramsPerUnit: Bool { primitiveValue(forKey: "gramsPerUnit") != nil }
    var hasMillilitresPerUnit: Bool { primitiveValue(forKey: "millilitresPerUnit") != nil }
}

@objc(RecipeStep)
final class RecipeStep: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var instruction: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var recipe: Recipe?

    static func fetchRequest() -> NSFetchRequest<RecipeStep> {
        NSFetchRequest(entityName: "RecipeStep")
    }
}

@objc(MealPlanEntry)
final class MealPlanEntry: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var mealType: String?
    @NSManaged var isLeftover: Bool
    @NSManaged var isOfficeDay: Bool
    @NSManaged var displayNameOverride: String?
    @NSManaged var plannedServings: Double
    @NSManaged var servingsPrepared: Double
    @NSManaged var servingsEaten: Double
    @NSManaged var household: Household?
    @NSManaged var recipe: Recipe?
    @NSManaged var leftoverSource: MealPlanEntry?
    @NSManaged var leftoverMeals: NSSet?

    static func fetchRequest() -> NSFetchRequest<MealPlanEntry> {
        NSFetchRequest(entityName: "MealPlanEntry")
    }

    var displayName: String {
        if let override = displayNameOverride, !override.isEmpty { return override }
        let base = recipe?.name ?? "Meal"
        return isLeftover ? "Leftover \(base)" : base
    }

    var effectiveServingsPrepared: Double {
        if isLeftover { return 0 }
        return servingsPrepared > 0 ? servingsPrepared : max(plannedServings, 1)
    }

    var effectiveServingsEaten: Double {
        servingsEaten > 0 ? servingsEaten : (isLeftover ? max(plannedServings, 1) : min(2, max(plannedServings, 1)))
    }
}

@objc(FoodNutritionProfile)
final class FoodNutritionProfile: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var displayName: String?
    @NSManaged var brand: String?
    @NSManaged var sourceKind: String?
    @NSManaged var sourceReference: String?
    @NSManaged var sourceVersion: String?
    @NSManaged var preparationState: String?
    @NSManaged var basisQuantity: Double
    @NSManaged var basisUnit: String?
    @NSManaged var energyKcal: Double
    @NSManaged var proteinG: Double
    @NSManaged var household: Household?
    @NSManaged var recipeIngredients: NSSet?

    static func fetchRequest() -> NSFetchRequest<FoodNutritionProfile> {
        NSFetchRequest(entityName: "FoodNutritionProfile")
    }
}

@objc(ShoppingCategory)
final class ShoppingCategory: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var household: Household?

    static func fetchRequest() -> NSFetchRequest<ShoppingCategory> {
        NSFetchRequest(entityName: "ShoppingCategory")
    }
}

@objc(ShoppingItem)
final class ShoppingItem: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: Double
    @NSManaged var unit: String?
    @NSManaged var categoryName: String?
    @NSManaged var isChecked: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var generatedForWeekStart: Date?
    @NSManaged var household: Household?

    static func fetchRequest() -> NSFetchRequest<ShoppingItem> {
        NSFetchRequest(entityName: "ShoppingItem")
    }

    var hasQuantity: Bool {
        primitiveValue(forKey: "quantity") != nil
    }
}
