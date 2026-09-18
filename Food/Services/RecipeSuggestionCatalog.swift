import Foundation

struct SuggestedIngredientDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let amount: Double?
    let unit: String?
    let nutritionAmount: Double?
    let nutritionUnit: String?
    let category: ShoppingCategoryName
    let note: String?
    let isPantryStaple: Bool
    let isExcludedFromNutrition: Bool
    let gramsPerUnit: Double?
    let sourceReference: String?
    let preparationState: String?
    let basisUnit: String
    let caloriesPer100: Double
    let proteinPer100: Double

    var nutritionIngredient: NutritionIngredient {
        NutritionIngredient(
            name: name,
            amount: nutritionAmount ?? amount,
            unit: nutritionUnit ?? unit,
            basisQuantity: 100,
            basisUnit: basisUnit,
            caloriesPerBasis: caloriesPer100,
            proteinPerBasis: proteinPer100,
            gramsPerUnit: gramsPerUnit,
            isExcluded: isExcludedFromNutrition
        )
    }

    func copiedWithNewID() -> SuggestedIngredientDraft {
        SuggestedIngredientDraft(
            id: UUID(),
            name: name,
            amount: amount,
            unit: unit,
            nutritionAmount: nutritionAmount,
            nutritionUnit: nutritionUnit,
            category: category,
            note: note,
            isPantryStaple: isPantryStaple,
            isExcludedFromNutrition: isExcludedFromNutrition,
            gramsPerUnit: gramsPerUnit,
            sourceReference: sourceReference,
            preparationState: preparationState,
            basisUnit: basisUnit,
            caloriesPer100: caloriesPer100,
            proteinPer100: proteinPer100
        )
    }
}

struct RecipeSuggestionDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let mealType: MealType
    let defaultServings: Double
    let tags: [String]
    let cookingRequired: Bool
    let isOfficeFriendly: Bool
    let isBatchCook: Bool
    let ingredients: [SuggestedIngredientDraft]
    let steps: [String]

    var nutrition: NutritionCalculation {
        NutritionCalculator.calculate(
            ingredients: ingredients.map(\.nutritionIngredient),
            servings: defaultServings
        )
    }

    var planningRecipe: PlanningRecipe {
        let calculated = nutrition
        return PlanningRecipe(
            id: id,
            name: name,
            mealTypes: [mealType],
            defaultServings: defaultServings,
            caloriesPerServing: calculated.isComplete ? calculated.perServing.calories : nil,
            proteinPerServing: calculated.isComplete ? calculated.perServing.proteinGrams : nil,
            isOfficeFriendly: isOfficeFriendly,
            isBatchCook: isBatchCook,
            isNew: true
        )
    }

    func replacingCopy(
        id: UUID = UUID(),
        name: String,
        description: String,
        steps: [String]
    ) -> RecipeSuggestionDraft {
        RecipeSuggestionDraft(
            id: id,
            name: name,
            description: description,
            mealType: mealType,
            defaultServings: defaultServings,
            tags: tags,
            cookingRequired: cookingRequired,
            isOfficeFriendly: isOfficeFriendly,
            isBatchCook: isBatchCook,
            ingredients: ingredients.map { $0.copiedWithNewID() },
            steps: steps
        )
    }
}

enum RecipeSuggestionCatalog {
    static let suggestions: [RecipeSuggestionDraft] = [
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!,
            name: "Smoky Tofu Lentil Pasta",
            description: "A rich tomato pasta with tofu and lentils for a filling, high-protein dinner.",
            mealType: .dinner,
            defaultServings: 4,
            tags: ["Dinner", "High protein"],
            cookingRequired: true,
            isOfficeFriendly: false,
            isBatchCook: true,
            ingredients: [
                food("wholewheat pasta", 300, "g", .cupboard, "11-718", "dry", 329, 12.6),
                food("drained cooked lentils", 480, "g", .cupboard, "13-661", "boiled", 92, 7.8),
                food("tofu", 600, "g", .fridge, "13-570", "steamed", 73, 8.1),
                food("chopped tomatoes", 800, "g", .cupboard, "13-530", "canned", 19, 1.1),
                food("mushrooms", 400, "g", .fruitAndVeg, "13-505", "raw", 7, 1),
                food("spinach", 200, "g", .fruitAndVeg, "13-521", "raw", 16, 2.6),
                food("cooking oil", 20, "g", .cupboard, "17-041", "as sold", 899, 0),
                pantry("smoked paprika"),
                pantry("black pepper")
            ],
            steps: [
                "Cook the pasta according to the packet instructions.",
                "Brown the tofu in the oil, then add the mushrooms.",
                "Stir in the tomatoes, lentils and smoked paprika and simmer for 10 minutes.",
                "Fold in the spinach until wilted.",
                "Drain the pasta, combine with the sauce and divide evenly."
            ]
        ),
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000002")!,
            name: "Chickpea Potato Curry Bowls",
            description: "A tomato-based chickpea and potato curry served with a measured rice portion.",
            mealType: .dinner,
            defaultServings: 4,
            tags: ["Dinner"],
            cookingRequired: true,
            isOfficeFriendly: false,
            isBatchCook: true,
            ingredients: [
                food("drained chickpeas", 480, "g", .cupboard, "13-670", "canned, drained", 129, 8.4),
                food("potatoes", 600, "g", .fruitAndVeg, "13-489", "raw", 82, 1.9),
                food("basmati rice", 240, "g", .cupboard, "11-857", "raw", 351, 8.1),
                food("chopped tomatoes", 800, "g", .cupboard, "13-530", "canned", 19, 1.1),
                food("spinach", 200, "g", .fruitAndVeg, "13-521", "raw", 16, 2.6),
                food("cooking oil", 20, "g", .cupboard, "17-041", "as sold", 899, 0),
                pantry("curry powder")
            ],
            steps: [
                "Cook the rice.",
                "Cut the potatoes into small cubes.",
                "Heat the oil, add the curry powder and potatoes, and cook for 3 minutes.",
                "Add the tomatoes and chickpeas and simmer until the potatoes are tender.",
                "Stir in the spinach and serve over the rice."
            ]
        ),
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000003")!,
            name: "Peanut Tofu Noodles",
            description: "Wholewheat noodles, tofu and vegetables in a measured peanut sauce.",
            mealType: .dinner,
            defaultServings: 2,
            tags: ["Dinner", "High protein"],
            cookingRequired: true,
            isOfficeFriendly: false,
            isBatchCook: false,
            ingredients: [
                food("wholewheat pasta", 150, "g", .cupboard, "11-718", "dry", 329, 12.6, note: "use noodles if available"),
                food("tofu", 400, "g", .fridge, "13-570", "steamed", 73, 8.1),
                food("peanut butter", 60, "g", .cupboard, "14-892", "as sold", 607, 22.8),
                food("green pepper", 200, "g", .fruitAndVeg, "13-318", "raw", 15, 0.8),
                food("spinach", 100, "g", .fruitAndVeg, "13-521", "raw", 16, 2.6),
                food("cooking oil", 10, "g", .cupboard, "17-041", "as sold", 899, 0),
                pantry("chilli")
            ],
            steps: [
                "Cook the pasta or noodles.",
                "Brown the tofu in the oil and add the sliced pepper.",
                "Loosen the peanut butter with hot pasta water and add chilli to taste.",
                "Add the spinach, noodles and peanut sauce to the pan.",
                "Toss well and divide evenly."
            ]
        ),
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000004")!,
            name: "Tofu Burrito Rice Bowls",
            description: "A substantial tofu, bean and rice bowl with corn, pepper and avocado.",
            mealType: .dinner,
            defaultServings: 2,
            tags: ["Dinner", "High protein"],
            cookingRequired: true,
            isOfficeFriendly: false,
            isBatchCook: false,
            ingredients: [
                food("long-grain rice", 150, "g", .cupboard, "11-861", "raw", 355, 6.7),
                food("tofu", 400, "g", .fridge, "13-570", "steamed", 73, 8.1),
                food("drained kidney beans", 240, "g", .cupboard, "13-660", "canned, drained", 100, 8.6),
                food("sweetcorn", 150, "g", .cupboard, "13-529", "canned, drained", 78, 2.6),
                food("avocado", 100, "g", .fruitAndVeg, "14-386", "flesh only", 171, 1.8),
                food("green pepper", 200, "g", .fruitAndVeg, "13-318", "raw", 15, 0.8),
                food("chopped tomatoes", 400, "g", .cupboard, "13-530", "canned", 19, 1.1),
                pantry("ground cumin")
            ],
            steps: [
                "Cook the rice.",
                "Brown the tofu with cumin and sliced pepper.",
                "Warm the beans, sweetcorn and tomatoes together.",
                "Divide the rice, tofu and bean mixture between bowls.",
                "Top with the avocado."
            ]
        ),
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000005")!,
            name: "Tofu Potato Breakfast Hash",
            description: "A substantial weekend breakfast with tofu, potatoes, greens and toast.",
            mealType: .breakfast,
            defaultServings: 2,
            tags: ["Breakfast", "High protein"],
            cookingRequired: true,
            isOfficeFriendly: false,
            isBatchCook: false,
            ingredients: [
                food("tofu", 300, "g", .fridge, "13-570", "steamed", 73, 8.1),
                food("potatoes", 300, "g", .fruitAndVeg, "13-489", "raw", 82, 1.9),
                food("mushrooms", 150, "g", .fruitAndVeg, "13-505", "raw", 7, 1),
                food("spinach", 100, "g", .fruitAndVeg, "13-521", "raw", 16, 2.6),
                food("wholemeal bread", 140, "g", .bread, "11-981", "as sold", 217, 9.4),
                food("cooking oil", 10, "g", .cupboard, "17-041", "as sold", 899, 0),
                pantry("smoked paprika")
            ],
            steps: [
                "Dice and boil the potatoes until almost tender.",
                "Heat the oil and brown the potatoes and mushrooms.",
                "Crumble in the tofu and season with smoked paprika.",
                "Add the spinach and cook until wilted.",
                "Serve with the toast."
            ]
        ),
        RecipeSuggestionDraft(
            id: UUID(uuidString: "C1000000-0000-0000-0000-000000000006")!,
            name: "Lentil Chickpea Wraps",
            description: "Portable wraps with lentils, chickpeas, houmous and crisp lettuce.",
            mealType: .lunch,
            defaultServings: 1,
            tags: ["Lunch", "Office"],
            cookingRequired: false,
            isOfficeFriendly: true,
            isBatchCook: false,
            ingredients: [
                itemFood("large wholemeal wraps", 1, .bread, gramsPerItem: 70, "11-925", "as sold", 285, 7.8),
                food("drained cooked lentils", 120, "g", .cupboard, "13-661", "boiled", 92, 7.8),
                food("drained chickpeas", 60, "g", .cupboard, "13-670", "canned, drained", 129, 8.4),
                food("hummus", 25, "g", .fridge, "13-556", "as sold", 307, 6.8),
                food("lettuce", 40, "g", .fruitAndVeg, "13-520", "raw", 11, 1.2),
                pantry("black pepper")
            ],
            steps: [
                "Roughly mash the lentils, chickpeas and houmous together.",
                "Season with black pepper.",
                "Keep the filling and lettuce separate until serving if preparing for work.",
                "Divide between the wraps and add the lettuce."
            ]
        )
    ]

    private static func food(
        _ name: String,
        _ amount: Double,
        _ unit: String,
        _ category: ShoppingCategoryName,
        _ sourceReference: String,
        _ preparationState: String,
        _ calories: Double,
        _ protein: Double,
        note: String? = nil
    ) -> SuggestedIngredientDraft {
        SuggestedIngredientDraft(
            id: UUID(),
            name: name,
            amount: amount,
            unit: unit,
            nutritionAmount: amount,
            nutritionUnit: unit,
            category: category,
            note: note,
            isPantryStaple: false,
            isExcludedFromNutrition: false,
            gramsPerUnit: nil,
            sourceReference: sourceReference,
            preparationState: preparationState,
            basisUnit: "g",
            caloriesPer100: calories,
            proteinPer100: protein
        )
    }

    private static func itemFood(
        _ name: String,
        _ amount: Double,
        _ category: ShoppingCategoryName,
        gramsPerItem: Double,
        _ sourceReference: String,
        _ preparationState: String,
        _ calories: Double,
        _ protein: Double
    ) -> SuggestedIngredientDraft {
        SuggestedIngredientDraft(
            id: UUID(),
            name: name,
            amount: amount,
            unit: nil,
            nutritionAmount: amount,
            nutritionUnit: "item",
            category: category,
            note: nil,
            isPantryStaple: false,
            isExcludedFromNutrition: false,
            gramsPerUnit: gramsPerItem,
            sourceReference: sourceReference,
            preparationState: preparationState,
            basisUnit: "g",
            caloriesPer100: calories,
            proteinPer100: protein
        )
    }

    private static func pantry(_ name: String) -> SuggestedIngredientDraft {
        SuggestedIngredientDraft(
            id: UUID(),
            name: name,
            amount: nil,
            unit: nil,
            nutritionAmount: nil,
            nutritionUnit: nil,
            category: .cupboard,
            note: "to taste",
            isPantryStaple: true,
            isExcludedFromNutrition: true,
            gramsPerUnit: nil,
            sourceReference: nil,
            preparationState: nil,
            basisUnit: "g",
            caloriesPer100: 0,
            proteinPer100: 0
        )
    }
}
