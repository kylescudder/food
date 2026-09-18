import CoreData
import Foundation

enum SeedData {
    static let currentVersion: Int16 = 2

    struct IngredientDefinition {
        let name: String
        let amount: Double?
        let unit: String?
        let category: ShoppingCategoryName
        let note: String?
        let pantryStaple: Bool

        init(
            _ name: String,
            _ amount: Double? = nil,
            _ unit: String? = nil,
            category: ShoppingCategoryName,
            note: String? = nil,
            pantryStaple: Bool = false
        ) {
            self.name = name
            self.amount = amount
            self.unit = unit
            self.category = category
            self.note = note
            self.pantryStaple = pantryStaple
        }
    }

    struct RecipeDefinition {
        let id: UUID
        let name: String
        let description: String
        let servings: Double
        let calories: Double?
        let protein: Double?
        let tags: String
        let cookingRequired: Bool
        let ingredients: [IngredientDefinition]
        let steps: [String]
    }

    struct PlanDefinition {
        let dayOffset: Int
        let mealType: MealType
        let recipeName: String
        let servings: Double
        let isLeftover: Bool
        let displayName: String?
    }

    struct NutritionProfileDefinition {
        let id: UUID
        let displayName: String
        let aliases: [String]
        let sourceReference: String
        let preparationState: String
        let basisUnit: String
        let calories: Double
        let protein: Double
    }

    @discardableResult
    static func seedIfNeeded(
        household: Household,
        in context: NSManagedObjectContext,
        weekContaining date: Date = .now
    ) throws -> Bool {
        guard household.seedVersion < currentVersion else { return false }

        let store = household.objectID.persistentStore
        var recipesByName: [String: Recipe] = [:]

        if household.seedVersion < 1 {
            for definition in recipes {
                let recipe = Recipe(context: context)
                assign(recipe, to: store, in: context)
                recipe.id = definition.id
                recipe.name = definition.name
                recipe.recipeDescription = definition.description
                recipe.defaultServings = definition.servings
                if let calories = definition.calories { recipe.caloriesPerServing = calories }
                if let protein = definition.protein { recipe.proteinPerServing = protein }
                recipe.nutritionNote = definition.calories == nil && definition.protein == nil
                    ? "Nutrition varies by the products and portions chosen."
                    : "Approximate estimate per serving from typical ingredient values; check product labels."
                recipe.tags = definition.tags
                recipe.cookingRequired = definition.cookingRequired
                recipe.createdAt = household.createdAt ?? .now
                recipe.isGenerated = false
                recipe.isInRotation = true
                recipe.household = household

                for (index, ingredientDefinition) in definition.ingredients.enumerated() {
                    let ingredient = RecipeIngredient(context: context)
                    assign(ingredient, to: store, in: context)
                    ingredient.id = UUID()
                    ingredient.name = ingredientDefinition.name
                    if let amount = ingredientDefinition.amount { ingredient.amount = amount }
                    ingredient.unit = ingredientDefinition.unit
                    ingredient.note = ingredientDefinition.note
                    ingredient.sortOrder = Int16(index)
                    ingredient.categoryName = ingredientDefinition.category.rawValue
                    ingredient.isPantryStaple = ingredientDefinition.pantryStaple
                    ingredient.recipe = recipe
                }

                for (index, instruction) in definition.steps.enumerated() {
                    let step = RecipeStep(context: context)
                    assign(step, to: store, in: context)
                    step.id = UUID()
                    step.instruction = instruction
                    step.sortOrder = Int16(index)
                    step.recipe = recipe
                }
                recipesByName[definition.name] = recipe
            }

            for (index, categoryName) in ShoppingCategoryName.allCases.enumerated() {
                let category = ShoppingCategory(context: context)
                assign(category, to: store, in: context)
                category.id = UUID()
                category.name = categoryName.rawValue
                category.sortOrder = Int16(index)
                category.household = household
            }

            let weekStart = WeekCalendar.weekStart(containing: date)
            for definition in plan {
                guard let recipe = recipesByName[definition.recipeName] else {
                    throw SeedError.missingRecipe(definition.recipeName)
                }
                let entry = MealPlanEntry(context: context)
                assign(entry, to: store, in: context)
                entry.id = UUID()
                entry.date = WeekCalendar.calendar.date(
                    byAdding: .day,
                    value: definition.dayOffset,
                    to: weekStart
                )
                entry.mealType = definition.mealType.rawValue
                entry.plannedServings = definition.servings
                entry.isLeftover = definition.isLeftover
                entry.displayNameOverride = definition.displayName
                entry.isOfficeDay = definition.dayOffset == 1 || definition.dayOffset == 2
                entry.recipe = recipe
                entry.household = household
            }
        }

        if recipesByName.isEmpty {
            let request = Recipe.fetchRequest()
            request.predicate = NSPredicate(format: "household == %@", household)
            for recipe in try context.fetch(request) {
                if let name = recipe.name { recipesByName[name] = recipe }
            }
        }

        if household.seedVersion < 2 {
            seedNutritionProfiles(
                household: household,
                recipes: Array(recipesByName.values),
                store: store,
                in: context
            )
            try migrateMealPlanEntries(household: household, in: context)
        }

        household.seedVersion = currentVersion
        try context.save()
        return true
    }

    private static func assign(
        _ object: NSManagedObject,
        to store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) {
        if let store { context.assign(object, to: store) }
    }

    private static func seedNutritionProfiles(
        household: Household,
        recipes: [Recipe],
        store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) {
        var profilesByAlias: [String: FoodNutritionProfile] = [:]

        for definition in nutritionProfiles {
            let profile = FoodNutritionProfile(context: context)
            assign(profile, to: store, in: context)
            profile.id = definition.id
            profile.displayName = definition.displayName
            profile.sourceKind = "CoFID"
            profile.sourceReference = definition.sourceReference
            profile.sourceVersion = "2021"
            profile.preparationState = definition.preparationState
            profile.basisQuantity = 100
            profile.basisUnit = definition.basisUnit
            profile.energyKcal = definition.calories
            profile.proteinG = definition.protein
            profile.household = household
            for alias in definition.aliases + [definition.displayName] {
                profilesByAlias[normalized(alias)] = profile
            }
        }

        for recipe in recipes {
            recipe.createdAt = recipe.createdAt ?? household.createdAt ?? .now
            recipe.isInRotation = true
            for ingredient in recipe.sortedIngredients {
                let key = normalized(ingredient.name ?? "")
                ingredient.nutritionProfile = profilesByAlias[key]
                if ingredient.hasAmount {
                    ingredient.nutritionAmount = ingredient.amount
                    ingredient.nutritionUnit = ingredient.unit
                }
                if ingredient.isPantryStaple && !ingredient.hasAmount {
                    ingredient.excludeFromNutrition = true
                }
                if key == normalized("large wholemeal wraps") {
                    ingredient.gramsPerUnit = 70
                    ingredient.nutritionUnit = "item"
                }
            }
        }
    }

    private static func migrateMealPlanEntries(
        household: Household,
        in context: NSManagedObjectContext
    ) throws {
        let request = MealPlanEntry.fetchRequest()
        request.predicate = NSPredicate(format: "household == %@", household)
        let entries = try context.fetch(request)

        for entry in entries {
            if entry.isLeftover {
                entry.servingsPrepared = 0
                entry.servingsEaten = max(entry.plannedServings, 1)
                entry.leftoverSource = entries
                    .filter {
                        !$0.isLeftover
                            && $0.recipe == entry.recipe
                            && ($0.date ?? .distantFuture) < (entry.date ?? .distantPast)
                    }
                    .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            } else {
                entry.servingsPrepared = max(entry.plannedServings, 1)
                entry.servingsEaten = entry.mealType == MealType.dinner.rawValue
                    ? min(2, entry.servingsPrepared)
                    : 1
            }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    enum SeedError: LocalizedError {
        case missingRecipe(String)

        var errorDescription: String? {
            switch self {
            case .missingRecipe(let name): "The seed plan references a missing recipe: \(name)."
            }
        }
    }
}

private extension SeedData {
    static let nutritionProfiles: [NutritionProfileDefinition] = [
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!, displayName: "Porridge oats", aliases: ["oats"], sourceReference: "11-788", preparationState: "dry", basisUnit: "g", calories: 381, protein: 10.9),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!, displayName: "Tofu", aliases: ["tofu", "shawarma-marinated tofu"], sourceReference: "13-570", preparationState: "steamed", basisUnit: "g", calories: 73, protein: 8.1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!, displayName: "Chickpeas", aliases: ["drained chickpeas"], sourceReference: "13-670", preparationState: "canned, drained", basisUnit: "g", calories: 129, protein: 8.4),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000004")!, displayName: "Kidney beans", aliases: ["drained kidney beans"], sourceReference: "13-660", preparationState: "canned, drained", basisUnit: "g", calories: 100, protein: 8.6),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000005")!, displayName: "Lentils", aliases: ["drained cooked lentils"], sourceReference: "13-661", preparationState: "boiled", basisUnit: "g", calories: 92, protein: 7.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000006")!, displayName: "Chopped tomatoes", aliases: ["chopped tomatoes"], sourceReference: "13-530", preparationState: "canned", basisUnit: "g", calories: 19, protein: 1.1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000007")!, displayName: "Tomato puree", aliases: ["tomato puree"], sourceReference: "13-531", preparationState: "as sold", basisUnit: "g", calories: 67, protein: 4.4),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000008")!, displayName: "Basmati rice", aliases: ["basmati rice"], sourceReference: "11-857", preparationState: "raw", basisUnit: "g", calories: 351, protein: 8.1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000009")!, displayName: "Long-grain rice", aliases: ["long-grain rice"], sourceReference: "11-861", preparationState: "raw", basisUnit: "g", calories: 355, protein: 6.7),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000A")!, displayName: "Wholewheat pasta", aliases: ["wholewheat pasta"], sourceReference: "11-718", preparationState: "dry", basisUnit: "g", calories: 329, protein: 12.6),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000B")!, displayName: "Houmous", aliases: ["hummus"], sourceReference: "13-556", preparationState: "as sold", basisUnit: "g", calories: 307, protein: 6.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000C")!, displayName: "Peanut butter", aliases: ["peanut butter"], sourceReference: "14-892", preparationState: "as sold", basisUnit: "g", calories: 607, protein: 22.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000D")!, displayName: "Onion", aliases: ["onion", "red onion"], sourceReference: "13-499", preparationState: "raw", basisUnit: "g", calories: 35, protein: 1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000E")!, displayName: "Green pepper", aliases: ["green pepper", "peppers"], sourceReference: "13-318", preparationState: "raw", basisUnit: "g", calories: 15, protein: 0.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000000F")!, displayName: "Mushrooms", aliases: ["mushrooms"], sourceReference: "13-505", preparationState: "raw", basisUnit: "g", calories: 7, protein: 1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000010")!, displayName: "Spinach", aliases: ["spinach"], sourceReference: "13-521", preparationState: "raw", basisUnit: "g", calories: 16, protein: 2.6),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000011")!, displayName: "Sweetcorn", aliases: ["sweetcorn"], sourceReference: "13-529", preparationState: "canned, drained", basisUnit: "g", calories: 78, protein: 2.6),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000012")!, displayName: "Potatoes", aliases: ["potatoes"], sourceReference: "13-489", preparationState: "raw", basisUnit: "g", calories: 82, protein: 1.9),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000013")!, displayName: "Wheat tortilla", aliases: ["large wholemeal wraps"], sourceReference: "11-925", preparationState: "as sold", basisUnit: "g", calories: 285, protein: 7.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000014")!, displayName: "Wholemeal bread", aliases: ["wholemeal bread"], sourceReference: "11-981", preparationState: "as sold", basisUnit: "g", calories: 217, protein: 9.4),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000015")!, displayName: "Avocado", aliases: ["avocado"], sourceReference: "14-386", preparationState: "flesh only", basisUnit: "g", calories: 171, protein: 1.8),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000016")!, displayName: "Carrots", aliases: ["carrots"], sourceReference: "13-496", preparationState: "raw", basisUnit: "g", calories: 34, protein: 0.5),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000017")!, displayName: "Cucumber", aliases: ["cucumber"], sourceReference: "13-523", preparationState: "raw", basisUnit: "g", calories: 14, protein: 1),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000018")!, displayName: "Lettuce", aliases: ["lettuce", "salad leaves"], sourceReference: "13-520", preparationState: "raw", basisUnit: "g", calories: 11, protein: 1.2),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-000000000019")!, displayName: "Blueberries", aliases: ["berries"], sourceReference: "14-325", preparationState: "raw", basisUnit: "g", calories: 40, protein: 0.9),
        .init(id: UUID(uuidString: "B1000000-0000-0000-0000-00000000001A")!, displayName: "Rapeseed oil", aliases: ["cooking oil"], sourceReference: "17-041", preparationState: "as sold", basisUnit: "g", calories: 899, protein: 0)
    ]

    static let recipes: [RecipeDefinition] = [
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!,
            name: "Protein Porridge",
            description: "A deliberately smaller, smooth high-protein porridge portion.",
            servings: 1,
            calories: 375,
            protein: 26,
            tags: "Breakfast,High protein",
            cookingRequired: true,
            ingredients: [
                .init("oats", 40, "g", category: .cupboard),
                .init("unsweetened soy milk", 200, "ml", category: .dairy),
                .init("vegan protein powder", 15, "g", category: .cupboard),
                .init("berries", 100, "g", category: .fruitAndVeg, note: "or ½ banana per serving"),
                .init("peanut butter", 7.5, "g", category: .cupboard, note: "5–10 g per serving, to taste"),
                .init("cinnamon", category: .cupboard, note: "optional", pantryStaple: true)
            ],
            steps: [
                "Cook the oats and soy milk.",
                "Remove the porridge from the heat. Do not cook the protein powder with the oats.",
                "Separately mix the protein powder with a small amount of cold soy milk into a smooth paste.",
                "Stir the protein mixture into the cooked porridge.",
                "Add the fruit.",
                "Add peanut butter and cinnamon, if using."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!,
            name: "Overnight Oats",
            description: "A corrected, portable portion for an office morning without a powdery texture.",
            servings: 1,
            calories: 400,
            protein: 27,
            tags: "Breakfast,Office,No cook",
            cookingRequired: false,
            ingredients: [
                .init("oats", 40, "g", category: .cupboard),
                .init("unsweetened soy milk", 200, "ml", category: .dairy),
                .init("vegan protein powder", 15, "g", category: .cupboard),
                .init("chia seeds", 5, "g", category: .cupboard),
                .init("berries", 100, "g", category: .fruitAndVeg, note: "or ½ banana per serving"),
                .init("peanut butter", 7.5, "g", category: .cupboard, note: "5–10 g per serving, to taste"),
                .init("cinnamon", category: .cupboard, note: "optional", pantryStaple: true)
            ],
            steps: [
                "Mix the protein powder with a small amount of soy milk first until smooth.",
                "Add the oats and chia seeds to a container.",
                "Add the remaining soy milk.",
                "Add the smooth protein mixture.",
                "Stir thoroughly.",
                "Add berries or banana.",
                "Add peanut butter.",
                "Cover and refrigerate overnight."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!,
            name: "Chickpea Wrap",
            description: "A quick lunch wrap. Keep the components separate overnight so the wrap stays dry.",
            servings: 1,
            calories: 490,
            protein: 22,
            tags: "Lunch,No cook,Office",
            cookingRequired: false,
            ingredients: [
                .init("large wholemeal wraps", 1, nil, category: .bread),
                .init("drained chickpeas", 120, "g", category: .cupboard),
                .init("hummus", 25, "g", category: .fridge),
                .init("lettuce", 40, "g", category: .fruitAndVeg),
                .init("tomato", 1, nil, category: .fruitAndVeg),
                .init("cucumber", 0.25, nil, category: .fruitAndVeg),
                .init("pickled onion", 30, "g", category: .cupboard),
                .init("salsa", 30, "g", category: .cupboard),
                .init("smoked paprika", category: .cupboard, note: "to taste", pantryStaple: true),
                .init("chilli", category: .cupboard, note: "to taste", pantryStaple: true),
                .init("black pepper", category: .cupboard, note: "to taste", pantryStaple: true)
            ],
            steps: [
                "Roughly mash the chickpeas with the hummus.",
                "Season to taste.",
                "Prepare the salad.",
                "Warm the wrap, if desired.",
                "Assemble immediately before eating.",
                "For an office lunch, store filling and salad separately overnight and assemble in the morning."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!,
            name: "Shawarma Tofu Wraps",
            description: "Two generously filled wraps using the tested tofu portion—without chickpeas.",
            servings: 2,
            calories: 510,
            protein: 32,
            tags: "Dinner,High protein",
            cookingRequired: true,
            ingredients: [
                .init("shawarma-marinated tofu", 275, "g", category: .fridge),
                .init("red onion", 0.5, nil, category: .fruitAndVeg),
                .init("green pepper", 1, nil, category: .fruitAndVeg),
                .init("large wholemeal wraps", 2, nil, category: .bread),
                .init("lettuce", 60, "g", category: .fruitAndVeg),
                .init("tomato", 1, nil, category: .fruitAndVeg),
                .init("cucumber", 0.5, nil, category: .fruitAndVeg),
                .init("hummus", 50, "g", category: .fridge, note: "about 20–30 g per serving"),
                .init("chilli sauce or salsa", category: .cupboard, note: "optional")
            ],
            steps: [
                "Slice the pepper and onion.",
                "Heat a frying pan.",
                "Cook the marinated tofu until browned. Avoid extra oil if the marinade already contains oil.",
                "Add the pepper and onion.",
                "Cook until softened but still with some bite.",
                "Warm the wraps.",
                "Spread hummus onto the wraps.",
                "Add lettuce, tomato and cucumber.",
                "Divide the tofu mixture evenly between the wraps.",
                "Add chilli sauce or salsa, if wanted.",
                "Wrap and serve."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!,
            name: "Lentil + TVP Bolognese",
            description: "Four adult portions: Tuesday dinner for two plus Wednesday lunch leftovers.",
            servings: 4,
            calories: 635,
            protein: 45,
            tags: "Dinner,Batch cook,High protein",
            cookingRequired: true,
            ingredients: [
                .init("wholewheat pasta", 300, "g", category: .cupboard),
                .init("drained cooked lentils", 480, "g", category: .cupboard, note: "typically 240 g drained per tin"),
                .init("TVP / dried soy mince", 150, "g", category: .cupboard),
                .init("chopped tomatoes", 800, "g", category: .cupboard, note: "400 g tins"),
                .init("tomato puree", 60, "g", category: .cupboard),
                .init("onion", 1, nil, category: .fruitAndVeg),
                .init("garlic", 3, "cloves", category: .fruitAndVeg),
                .init("carrots", 200, "g", category: .fruitAndVeg),
                .init("mushrooms", 250, "g", category: .fruitAndVeg),
                .init("Italian herbs", 2, "tsp", category: .cupboard, pantryStaple: true)
            ],
            steps: [
                "Rehydrate the TVP according to its packet.",
                "Dice the onion, carrots and mushrooms; mince the garlic.",
                "Soften the vegetables in a large pan, using a splash of water if needed.",
                "Stir in tomato puree and Italian herbs.",
                "Add chopped tomatoes, lentils and drained TVP.",
                "Simmer for 20–25 minutes, adding water if it becomes too thick.",
                "Cook the pasta and divide everything into four even portions."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000006")!,
            name: "Bean + TVP Chilli with Rice",
            description: "Four portions: Wednesday dinner for two plus Thursday lunch leftovers.",
            servings: 4,
            calories: 620,
            protein: 39,
            tags: "Dinner,Batch cook,High protein",
            cookingRequired: true,
            ingredients: [
                .init("drained kidney beans", 240, "g", category: .cupboard, note: "typically 240 g drained per tin"),
                .init("drained black beans", 240, "g", category: .cupboard, note: "typically 240 g drained per tin"),
                .init("TVP / dried soy mince", 150, "g", category: .cupboard),
                .init("chopped tomatoes", 800, "g", category: .cupboard, note: "400 g tins"),
                .init("peppers", 2, nil, category: .fruitAndVeg),
                .init("onion", 1, nil, category: .fruitAndVeg),
                .init("sweetcorn", 200, "g", category: .freezer),
                .init("long-grain rice", 260, "g", category: .cupboard),
                .init("chilli powder", 2, "tsp", category: .cupboard, pantryStaple: true),
                .init("ground cumin", 2, "tsp", category: .cupboard, pantryStaple: true),
                .init("smoked paprika", 2, "tsp", category: .cupboard, pantryStaple: true)
            ],
            steps: [
                "Rehydrate the TVP according to its packet.",
                "Dice the peppers and onion, then soften them in a large pan.",
                "Add chilli, cumin and smoked paprika; cook briefly.",
                "Add tomatoes, beans, sweetcorn and drained TVP.",
                "Simmer for 20 minutes.",
                "Cook the rice and divide the chilli and rice into four even portions."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000007")!,
            name: "Tofu Curry with Rice",
            description: "A tomato-led curry with just enough light coconut milk for creaminess.",
            servings: 2,
            calories: 650,
            protein: 41,
            tags: "Dinner,High protein",
            cookingRequired: true,
            ingredients: [
                .init("tofu", 350, "g", category: .fridge),
                .init("mixed vegetables", 400, "g", category: .fruitAndVeg),
                .init("chopped tomatoes", 400, "g", category: .cupboard, note: "400 g tins"),
                .init("light coconut milk", 100, "ml", category: .cupboard),
                .init("basmati rice", 140, "g", category: .cupboard),
                .init("curry paste", 2, "tbsp", category: .cupboard)
            ],
            steps: [
                "Press and cube the tofu, then brown it in a wide pan.",
                "Add the vegetables and cook for 5 minutes.",
                "Stir in the curry paste.",
                "Add the tomatoes and light coconut milk, then simmer until the vegetables are tender.",
                "Cook the rice and serve the curry in two even portions."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000008")!,
            name: "Vegan Burger, Potato Wedges & Vegetables",
            description: "A straightforward Friday dinner; exact nutrition depends heavily on the burgers and buns chosen.",
            servings: 2,
            calories: nil,
            protein: nil,
            tags: "Dinner,Easy",
            cookingRequired: true,
            ingredients: [
                .init("vegan burgers", 2, nil, category: .fridge),
                .init("potatoes", 500, "g", category: .fruitAndVeg),
                .init("wholemeal burger buns", 2, nil, category: .bread, note: "optional"),
                .init("mixed vegetables or salad", 300, "g", category: .fruitAndVeg),
                .init("cooking oil", 2, "tsp", category: .cupboard, note: "use sparingly", pantryStaple: true)
            ],
            steps: [
                "Cut the potatoes into wedges and toss with no more than 2 teaspoons of oil and seasoning.",
                "Bake the wedges until crisp and tender.",
                "Cook the burgers according to their packet.",
                "Prepare the vegetables or salad.",
                "Serve with buns, if using."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000009")!,
            name: "Tofu Scramble on Toast",
            description: "A simple savoury weekend breakfast for two.",
            servings: 2,
            calories: 430,
            protein: 30,
            tags: "Breakfast,High protein",
            cookingRequired: true,
            ingredients: [
                .init("tofu", 300, "g", category: .fridge),
                .init("wholemeal bread", 4, "slices", category: .bread),
                .init("mushrooms", 150, "g", category: .fruitAndVeg),
                .init("spinach", 100, "g", category: .fruitAndVeg),
                .init("tomato", 2, nil, category: .fruitAndVeg),
                .init("turmeric", 0.5, "tsp", category: .cupboard, pantryStaple: true),
                .init("nutritional yeast", 2, "tbsp", category: .cupboard)
            ],
            steps: [
                "Crumble the tofu into a large frying pan.",
                "Add turmeric and nutritional yeast, then season.",
                "Add the mushrooms, spinach and tomatoes and cook until tender.",
                "Toast the bread and divide the scramble evenly between two plates."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000010")!,
            name: "Leftovers / Light Lunch",
            description: "Use available leftovers or assemble a small balanced lunch. This flexible slot does not generate fixed groceries.",
            servings: 1,
            calories: nil,
            protein: nil,
            tags: "Lunch,Flexible",
            cookingRequired: false,
            ingredients: [],
            steps: ["Check the fridge for leftovers.", "Add fruit or vegetables and a protein source if the meal needs rounding out."]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000011")!,
            name: "Burrito Bowls",
            description: "Colourful rice bowls with beans and tofu; avocado is optional.",
            servings: 2,
            calories: 630,
            protein: 35,
            tags: "Dinner,High protein",
            cookingRequired: true,
            ingredients: [
                .init("long-grain rice", 130, "g", category: .cupboard),
                .init("drained black beans", 240, "g", category: .cupboard, note: "typically 240 g drained per tin"),
                .init("tofu", 250, "g", category: .fridge),
                .init("lettuce", 100, "g", category: .fruitAndVeg),
                .init("tomato", 2, nil, category: .fruitAndVeg),
                .init("salsa", 100, "g", category: .cupboard),
                .init("pepper", 1, nil, category: .fruitAndVeg),
                .init("sweetcorn", 100, "g", category: .freezer),
                .init("avocado", 1, nil, category: .fruitAndVeg, note: "optional")
            ],
            steps: [
                "Cook the rice.",
                "Cube and brown the tofu with your preferred Mexican-style seasoning.",
                "Warm the beans and sweetcorn.",
                "Chop the lettuce, tomatoes and pepper.",
                "Divide between two bowls and finish with salsa and optional avocado."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000012")!,
            name: "Protein Pancakes / Porridge",
            description: "Choose the seeded Protein Porridge, or make a modest pancake portion using the same breakfast staples.",
            servings: 1,
            calories: nil,
            protein: nil,
            tags: "Breakfast,Flexible",
            cookingRequired: true,
            ingredients: [
                .init("oats", 40, "g", category: .cupboard),
                .init("unsweetened soy milk", 150, "ml", category: .dairy),
                .init("vegan protein powder", 15, "g", category: .cupboard),
                .init("banana", 0.5, nil, category: .fruitAndVeg),
                .init("baking powder", 0.5, "tsp", category: .cupboard, pantryStaple: true)
            ],
            steps: [
                "For porridge, open the separate Protein Porridge recipe.",
                "For pancakes, blend the ingredients into a thick batter.",
                "Cook small pancakes in a non-stick pan until set and golden on both sides."
            ]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000013")!,
            name: "Soup + High-Protein Sandwich",
            description: "A flexible Sunday lunch built around soup and a protein-rich sandwich filling.",
            servings: 1,
            calories: nil,
            protein: nil,
            tags: "Lunch,Easy",
            cookingRequired: false,
            ingredients: [
                .init("vegan soup", 1, "portion", category: .cupboard),
                .init("wholemeal bread", 2, "slices", category: .bread),
                .init("high-protein vegan sandwich filling", 1, "portion", category: .fridge),
                .init("salad leaves", category: .fruitAndVeg)
            ],
            steps: ["Heat or serve the soup according to its instructions.", "Assemble the sandwich with the filling and salad leaves."]
        ),
        RecipeDefinition(
            id: UUID(uuidString: "A1000000-0000-0000-0000-000000000014")!,
            name: "Vegan Roast",
            description: "A flexible two-person roast: choose a vegan main, potatoes, plenty of vegetables and gravy.",
            servings: 2,
            calories: nil,
            protein: nil,
            tags: "Dinner,Flexible",
            cookingRequired: true,
            ingredients: [
                .init("vegan roast main", 2, "portions", category: .fridge),
                .init("potatoes", 500, "g", category: .fruitAndVeg),
                .init("seasonal vegetables", 500, "g", category: .fruitAndVeg),
                .init("vegan gravy", 2, "portions", category: .cupboard),
                .init("cooking oil", 2, "tsp", category: .cupboard, note: "use sparingly", pantryStaple: true)
            ],
            steps: [
                "Cook the vegan main according to its instructions.",
                "Roast or boil the potatoes using only as much oil as needed.",
                "Cook the vegetables.",
                "Make the gravy and serve everything between two plates."
            ]
        )
    ]

    static let plan: [PlanDefinition] = [
        .init(dayOffset: 0, mealType: .breakfast, recipeName: "Protein Porridge", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 0, mealType: .lunch, recipeName: "Chickpea Wrap", servings: 1, isLeftover: false, displayName: "Chickpea / Tofu Wrap"),
        .init(dayOffset: 0, mealType: .dinner, recipeName: "Shawarma Tofu Wraps", servings: 2, isLeftover: false, displayName: nil),
        .init(dayOffset: 1, mealType: .breakfast, recipeName: "Overnight Oats", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 1, mealType: .lunch, recipeName: "Chickpea Wrap", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 1, mealType: .dinner, recipeName: "Lentil + TVP Bolognese", servings: 4, isLeftover: false, displayName: nil),
        .init(dayOffset: 2, mealType: .breakfast, recipeName: "Overnight Oats", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 2, mealType: .lunch, recipeName: "Lentil + TVP Bolognese", servings: 2, isLeftover: true, displayName: "Leftover Lentil + TVP Bolognese"),
        .init(dayOffset: 2, mealType: .dinner, recipeName: "Bean + TVP Chilli with Rice", servings: 4, isLeftover: false, displayName: nil),
        .init(dayOffset: 3, mealType: .breakfast, recipeName: "Protein Porridge", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 3, mealType: .lunch, recipeName: "Bean + TVP Chilli with Rice", servings: 2, isLeftover: true, displayName: "Leftover Bean + TVP Chilli"),
        .init(dayOffset: 3, mealType: .dinner, recipeName: "Tofu Curry with Rice", servings: 2, isLeftover: false, displayName: nil),
        .init(dayOffset: 4, mealType: .breakfast, recipeName: "Protein Porridge", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 4, mealType: .lunch, recipeName: "Chickpea Wrap", servings: 1, isLeftover: false, displayName: "Tofu / Chickpea Wrap"),
        .init(dayOffset: 4, mealType: .dinner, recipeName: "Vegan Burger, Potato Wedges & Vegetables", servings: 2, isLeftover: false, displayName: nil),
        .init(dayOffset: 5, mealType: .breakfast, recipeName: "Tofu Scramble on Toast", servings: 2, isLeftover: false, displayName: nil),
        .init(dayOffset: 5, mealType: .lunch, recipeName: "Leftovers / Light Lunch", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 5, mealType: .dinner, recipeName: "Burrito Bowls", servings: 2, isLeftover: false, displayName: nil),
        .init(dayOffset: 6, mealType: .breakfast, recipeName: "Protein Pancakes / Porridge", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 6, mealType: .lunch, recipeName: "Soup + High-Protein Sandwich", servings: 1, isLeftover: false, displayName: nil),
        .init(dayOffset: 6, mealType: .dinner, recipeName: "Vegan Roast", servings: 2, isLeftover: false, displayName: nil)
    ]
}
