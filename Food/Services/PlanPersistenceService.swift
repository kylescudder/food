import CoreData
import Foundation

enum PlanPersistenceService {
    enum SaveError: LocalizedError {
        case missingRecipe(UUID)
        case incompletePlan

        var errorDescription: String? {
            switch self {
            case let .missingRecipe(id):
                "A planned recipe is no longer available (\(id.uuidString))."
            case .incompletePlan:
                "The proposed week does not contain breakfast, lunch and dinner for every day."
            }
        }
    }

    @discardableResult
    static func save(
        draft: WeeklyPlanDraft,
        newRecipeDrafts: [UUID: RecipeSuggestionDraft],
        household: Household,
        in context: NSManagedObjectContext
    ) throws -> [MealPlanEntry] {
        guard isComplete(draft) else {
            throw SaveError.incompletePlan
        }

        let store = household.objectID.persistentStore
        var recipesByID = try existingRecipes(household: household, in: context)
        var profilesByReference = try existingProfiles(household: household, in: context)

        for recipeID in Set(draft.entries.map(\.recipeID)) where recipesByID[recipeID] == nil {
            guard let suggestion = newRecipeDrafts[recipeID] else {
                throw SaveError.missingRecipe(recipeID)
            }
            recipesByID[recipeID] = makeRecipe(
                from: suggestion,
                household: household,
                store: store,
                profilesByReference: &profilesByReference,
                in: context
            )
        }

        let end = WeekCalendar.weekEnd(containing: draft.weekStart)
        let oldEntriesRequest = MealPlanEntry.fetchRequest()
        oldEntriesRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "household == %@", household),
            NSPredicate(
                format: "date >= %@ AND date < %@",
                draft.weekStart as NSDate,
                end as NSDate
            )
        ])
        try context.fetch(oldEntriesRequest).forEach(context.delete)

        var entriesByDraftID: [UUID: MealPlanEntry] = [:]
        for draftEntry in draft.entries {
            guard let recipe = recipesByID[draftEntry.recipeID] else {
                throw SaveError.missingRecipe(draftEntry.recipeID)
            }
            let entry = MealPlanEntry(context: context)
            assign(entry, to: store, in: context)
            entry.id = draftEntry.id
            entry.date = draftEntry.date
            entry.mealType = draftEntry.mealType.rawValue
            entry.isLeftover = draftEntry.isLeftover
            entry.isOfficeDay = draftEntry.isOfficeDay
            entry.plannedServings = draftEntry.isLeftover
                ? draftEntry.servingsEaten
                : draftEntry.servingsPrepared
            entry.servingsPrepared = draftEntry.servingsPrepared
            entry.servingsEaten = draftEntry.servingsEaten
            entry.recipe = recipe
            entry.household = household
            entriesByDraftID[draftEntry.id] = entry
        }

        for draftEntry in draft.entries where draftEntry.isLeftover {
            guard let sourceID = draftEntry.leftoverSourceID else { continue }
            entriesByDraftID[draftEntry.id]?.leftoverSource = entriesByDraftID[sourceID]
        }

        try context.save()
        return draft.entries.compactMap { entriesByDraftID[$0.id] }
    }

    private static func isComplete(_ draft: WeeklyPlanDraft) -> Bool {
        guard draft.entries.count == 21 else { return false }
        for dayOffset in 0..<7 {
            guard let date = WeekCalendar.calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: draft.weekStart
            ) else { return false }
            let mealTypes = Set(draft.entries.compactMap { entry -> MealType? in
                WeekCalendar.calendar.isDate(entry.date, inSameDayAs: date)
                    ? entry.mealType
                    : nil
            })
            guard mealTypes == Set(MealType.allCases) else { return false }
        }
        return true
    }

    private static func existingRecipes(
        household: Household,
        in context: NSManagedObjectContext
    ) throws -> [UUID: Recipe] {
        let request = Recipe.fetchRequest()
        request.predicate = NSPredicate(format: "household == %@", household)
        var result: [UUID: Recipe] = [:]
        for recipe in try context.fetch(request) {
            if let id = recipe.id { result[id] = recipe }
        }
        return result
    }

    private static func existingProfiles(
        household: Household,
        in context: NSManagedObjectContext
    ) throws -> [String: FoodNutritionProfile] {
        let request = FoodNutritionProfile.fetchRequest()
        request.predicate = NSPredicate(format: "household == %@", household)
        var result: [String: FoodNutritionProfile] = [:]
        for profile in try context.fetch(request) {
            if let reference = profile.sourceReference { result[reference] = profile }
        }
        return result
    }

    private static func makeRecipe(
        from draft: RecipeSuggestionDraft,
        household: Household,
        store: NSPersistentStore?,
        profilesByReference: inout [String: FoodNutritionProfile],
        in context: NSManagedObjectContext
    ) -> Recipe {
        let recipe = Recipe(context: context)
        assign(recipe, to: store, in: context)
        recipe.id = draft.id
        recipe.name = draft.name
        recipe.recipeDescription = draft.description
        recipe.defaultServings = draft.defaultServings
        recipe.tags = draft.tags.joined(separator: ",")
        recipe.cookingRequired = draft.cookingRequired
        recipe.createdAt = .now
        recipe.isGenerated = true
        recipe.isInRotation = true
        recipe.household = household

        let calculation = draft.nutrition
        if calculation.isComplete {
            recipe.caloriesPerServing = calculation.perServing.calories
            recipe.proteinPerServing = calculation.perServing.proteinGrams
            recipe.nutritionNote = "Approximate per-serving estimate calculated from the listed quantities and saved nutrition sources."
        }

        for (index, ingredientDraft) in draft.ingredients.enumerated() {
            let ingredient = RecipeIngredient(context: context)
            assign(ingredient, to: store, in: context)
            ingredient.id = ingredientDraft.id
            ingredient.name = ingredientDraft.name
            if let amount = ingredientDraft.amount { ingredient.amount = amount }
            ingredient.unit = ingredientDraft.unit
            ingredient.note = ingredientDraft.note
            ingredient.sortOrder = Int16(index)
            ingredient.categoryName = ingredientDraft.category.rawValue
            ingredient.isPantryStaple = ingredientDraft.isPantryStaple
            ingredient.excludeFromNutrition = ingredientDraft.isExcludedFromNutrition
            if let amount = ingredientDraft.nutritionAmount {
                ingredient.nutritionAmount = amount
            }
            ingredient.nutritionUnit = ingredientDraft.nutritionUnit
            if let grams = ingredientDraft.gramsPerUnit { ingredient.gramsPerUnit = grams }
            ingredient.recipe = recipe

            if let reference = ingredientDraft.sourceReference {
                let profile: FoodNutritionProfile
                if let existing = profilesByReference[reference] {
                    profile = existing
                } else {
                    profile = FoodNutritionProfile(context: context)
                    assign(profile, to: store, in: context)
                    profile.id = UUID()
                    profile.displayName = ingredientDraft.name
                    profile.sourceKind = "CoFID"
                    profile.sourceReference = reference
                    profile.sourceVersion = "2021"
                    profile.preparationState = ingredientDraft.preparationState
                    profile.basisQuantity = 100
                    profile.basisUnit = ingredientDraft.basisUnit
                    profile.energyKcal = ingredientDraft.caloriesPer100
                    profile.proteinG = ingredientDraft.proteinPer100
                    profile.household = household
                    profilesByReference[reference] = profile
                }
                ingredient.nutritionProfile = profile
            }
        }

        for (index, instruction) in draft.steps.enumerated() {
            let step = RecipeStep(context: context)
            assign(step, to: store, in: context)
            step.id = UUID()
            step.instruction = instruction
            step.sortOrder = Int16(index)
            step.recipe = recipe
        }

        return recipe
    }

    private static func assign(
        _ object: NSManagedObject,
        to store: NSPersistentStore?,
        in context: NSManagedObjectContext
    ) {
        if let store { context.assign(object, to: store) }
    }
}
