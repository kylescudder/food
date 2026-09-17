import CoreData
import Foundation

@objc(Household)
final class Household: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var seedVersion: Int16
    @NSManaged var recipes: NSSet?
    @NSManaged var mealPlanEntries: NSSet?
    @NSManaged var shoppingItems: NSSet?
    @NSManaged var categories: NSSet?

    static func fetchRequest() -> NSFetchRequest<Household> {
        NSFetchRequest(entityName: "Household")
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
    @NSManaged var recipe: Recipe?

    static func fetchRequest() -> NSFetchRequest<RecipeIngredient> {
        NSFetchRequest(entityName: "RecipeIngredient")
    }

    var hasAmount: Bool {
        entity.attributesByName["amount"]?.isOptional == false || primitiveValue(forKey: "amount") != nil
    }
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
    @NSManaged var household: Household?
    @NSManaged var recipe: Recipe?

    static func fetchRequest() -> NSFetchRequest<MealPlanEntry> {
        NSFetchRequest(entityName: "MealPlanEntry")
    }

    var displayName: String {
        if let override = displayNameOverride, !override.isEmpty { return override }
        let base = recipe?.name ?? "Meal"
        return isLeftover ? "Leftover \(base)" : base
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
    @NSManaged var household: Household?

    static func fetchRequest() -> NSFetchRequest<ShoppingItem> {
        NSFetchRequest(entityName: "ShoppingItem")
    }

    var hasQuantity: Bool {
        primitiveValue(forKey: "quantity") != nil
    }
}
