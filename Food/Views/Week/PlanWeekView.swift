import CoreData
import SwiftUI

struct PlanWeekView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @FetchRequest private var recipes: FetchedResults<Recipe>
    @FetchRequest private var historyEntries: FetchedResults<MealPlanEntry>

    let weekStart: Date
    let onSaved: () -> Void

    @State private var dailyTargetText: String
    @State private var unplannedReserveText: String
    @State private var isEditingTarget: Bool
    @State private var draft: WeeklyPlanDraft?
    @State private var planningRecipes: [UUID: PlanningRecipe] = [:]
    @State private var newRecipeDrafts: [UUID: RecipeSuggestionDraft] = [:]
    @State private var entryToSwap: WeeklyPlanDraftEntry?
    @State private var featuredSuggestionID: UUID?
    @State private var isSuggesting = false
    @State private var showingReplaceConfirmation = false
    @State private var errorMessage: String?

    init(household: Household, weekStart: Date, onSaved: @escaping () -> Void) {
        self.household = household
        self.weekStart = WeekCalendar.weekStart(containing: weekStart)
        self.onSaved = onSaved
        _dailyTargetText = State(initialValue: household.hasCalorieTarget
            ? QuantityText.format(household.kyleDailyCalorieTarget)
            : "")
        _unplannedReserveText = State(initialValue: household.hasCalorieTarget
            ? QuantityText.format(household.unplannedCalorieReserve)
            : "200")
        _isEditingTarget = State(initialValue: !household.hasCalorieTarget)
        _recipes = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
        _historyEntries = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \MealPlanEntry.date, ascending: false)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditingTarget {
                    targetForm
                } else if let draft {
                    reviewList(draft)
                } else {
                    ProgressView("Planning the week…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !isEditingTarget, draft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { attemptSave() }
                    }
                }
            }
            .onAppear {
                if !isEditingTarget, draft == nil { preparePlan() }
            }
            .sheet(item: $entryToSwap) { entry in
                let requiresBatch = draft?.entries.contains { $0.leftoverSourceID == entry.id } == true
                DraftRecipePickerView(
                    mealType: entry.mealType,
                    currentRecipeID: entry.recipeID,
                    recipes: planningRecipes.values
                        .filter {
                            $0.mealTypes.contains(entry.mealType)
                                && (!requiresBatch || $0.defaultServings >= 4)
                        }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                ) { recipe in
                    replace(entry, with: recipe)
                    entryToSwap = nil
                }
            }
            .confirmationDialog(
                "Replace the existing plan for this week?",
                isPresented: $showingReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace Plan", role: .destructive) { savePlan() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Recipes stay in the library. Only the dated meals for this week are replaced.")
            }
            .alert("Couldn’t Plan Week", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var title: String {
        if WeekCalendar.calendar.isDate(weekStart, inSameDayAs: WeekCalendar.weekStart()) {
            return "Plan This Week"
        }
        let nextWeek = WeekCalendar.calendar.date(byAdding: .day, value: 7, to: WeekCalendar.weekStart())
        if let nextWeek, WeekCalendar.calendar.isDate(weekStart, inSameDayAs: nextWeek) {
            return "Plan Next Week"
        }
        return "Plan Week"
    }

    private var targetForm: some View {
        Form {
            Section {
                TextField("Daily target", text: $dailyTargetText, prompt: Text("Enter Kyle’s target"))
                    .keyboardType(.numberPad)
                TextField("Room for snacks and drinks", text: $unplannedReserveText)
                    .keyboardType(.numberPad)
            } header: {
                Text("Kyle’s calorie budget")
            } footer: {
                Text("Enter the daily target Kyle has chosen. Food uses it to size meal suggestions; it does not calculate maintenance calories or apply this target to Rhiannon.")
            }

            Section {
                let budget = MealCalorieBudget(
                    dailyTarget: dailyTarget,
                    unplannedReserve: unplannedReserve
                )
                LabeledContent("Breakfast", value: "about \(QuantityText.format(budget.target(for: .breakfast))) kcal")
                LabeledContent("Lunch", value: "about \(QuantityText.format(budget.target(for: .lunch))) kcal")
                LabeledContent("Dinner", value: "about \(QuantityText.format(budget.target(for: .dinner))) kcal")
            } header: {
                Text("Planning split")
            } footer: {
                Text("These are planning guides, not a requirement to eat the same amount every day.")
            }

            Section {
                Button("Build My Week") { saveTargetAndBuild() }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!targetIsValid)
            }
        }
    }

    private func reviewList(_ draft: WeeklyPlanDraft) -> some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Kyle’s daily target")
                        Text("\(QuantityText.format(dailyTarget)) kcal · \(QuantityText.format(unplannedReserve)) kcal kept free")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") { isEditingTarget = true }
                }
            }

            ForEach(0..<7, id: \.self) { dayOffset in
                let date = WeekCalendar.calendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: draft.weekStart
                ) ?? draft.weekStart
                let entries = entries(on: date, in: draft)

                Section {
                    ForEach(entries) { entry in
                        let recipe = planningRecipes[entry.recipeID]
                        let canSwap = !entry.isLeftover
                        if canSwap {
                            Button {
                                entryToSwap = entry
                            } label: {
                                PlanMealRow(entry: entry, recipe: recipe, canSwap: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PlanMealRow(entry: entry, recipe: recipe, canSwap: canSwap)
                        }
                    }
                } header: {
                    HStack {
                        Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
                        if entries.contains(where: \.isOfficeDay) { Text("· OFFICE") }
                        Spacer()
                        if let calories = dailyCalories(on: date, in: draft) {
                            Text("KYLE ~\(QuantityText.format(calories)) KCAL")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Make Another Plan") { rebuildPlan(avoidingCurrentPlan: true) }
                if FreshRecipeSuggester.isAvailable {
                    Button {
                        requestFreshDinner()
                    } label: {
                        if isSuggesting {
                            HStack {
                                ProgressView()
                                Text("Creating a fresh dinner…")
                            }
                        } else {
                            Label("Create a Fresh Dinner", systemImage: "sparkles")
                        }
                    }
                    .disabled(isSuggesting)
                }
            } footer: {
                Text("New recipes are saved only when you save this plan. Nutrition is calculated from the listed ingredients; generated text never supplies the calorie total.")
            }
        }
    }

    private var targetIsValid: Bool {
        dailyTarget > 0 && unplannedReserve >= 0 && unplannedReserve < dailyTarget
    }

    private var dailyTarget: Double {
        NumberFormatter().number(from: dailyTargetText)?.doubleValue ?? 0
    }

    private var unplannedReserve: Double {
        NumberFormatter().number(from: unplannedReserveText)?.doubleValue ?? 0
    }

    private func saveTargetAndBuild() {
        guard targetIsValid else { return }
        household.kyleDailyCalorieTarget = dailyTarget
        household.unplannedCalorieReserve = unplannedReserve
        do {
            try persistence.saveViewContext()
            isEditingTarget = false
            preparePlan()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func preparePlan() {
        rebuildPlan()
        let existingIDs = Set(recipes.compactMap(\.id))
        let hasUsedBuiltInIdeas = RecipeSuggestionCatalog.suggestions.allSatisfy {
            existingIDs.contains($0.id)
        }
        let dinnerCount = recipes.compactMap { planningRecipe($0) }
            .filter { $0.mealTypes.contains(.dinner) }
            .count
        if hasUsedBuiltInIdeas,
           dinnerCount < 14,
           FreshRecipeSuggester.isAvailable,
           featuredSuggestionID == nil,
           !isSuggesting {
            requestFreshDinner()
        }
    }

    private func rebuildPlan(avoidingCurrentPlan: Bool = false) {
        let existingIDs = Set(recipes.compactMap(\.id))
        var availableDrafts = Dictionary(uniqueKeysWithValues: RecipeSuggestionCatalog.suggestions
            .filter { !existingIDs.contains($0.id) }
            .map { ($0.id, $0) })
        for (id, recipeDraft) in newRecipeDrafts where !RecipeSuggestionCatalog.suggestions.contains(where: { $0.id == id }) {
            availableDrafts[id] = recipeDraft
        }

        let savedRecipes = recipes
            .filter(\.isInRotation)
            .compactMap { planningRecipe($0) }
        let proposedRecipes = availableDrafts.values.map(\.planningRecipe)
        let allRecipes = savedRecipes + proposedRecipes
        planningRecipes = allRecipes.reduce(into: [:]) { result, recipe in
            result[recipe.id] = recipe
        }
        newRecipeDrafts = availableDrafts

        let cutoff = WeekCalendar.calendar.date(byAdding: .day, value: -28, to: weekStart) ?? .distantPast
        let history = historyEntries.compactMap { entry -> PlanningHistoryEntry? in
            guard let date = entry.date,
                  date >= cutoff,
                  date < weekStart,
                  let recipeID = entry.recipe?.id,
                  let mealType = MealType(rawValue: entry.mealType ?? "") else { return nil }
            return PlanningHistoryEntry(date: date, mealType: mealType, recipeID: recipeID)
        }
        var recentIDs = Set(history.map(\.recipeID))
        if avoidingCurrentPlan, let currentDraft = draft {
            recentIDs.formUnion(currentDraft.entries.map(\.recipeID))
        }
        if let featuredSuggestionID { recentIDs.remove(featuredSuggestionID) }

        let budget = MealCalorieBudget(
            dailyTarget: dailyTarget,
            unplannedReserve: unplannedReserve
        )
        let proposed = WeeklyPlanBuilder.build(
            weekStarting: weekStart,
            recipes: allRecipes,
            history: history,
            preferences: WeeklyPlanPreferences(
                officeWeekdays: [3, 4],
                batchCookingWeekdays: [3, 4],
                calorieRanges: budget.ranges,
                recentlyUsedRecipeIDs: recentIDs
            )
        )
        guard proposed.entries.count == 21 else {
            errorMessage = "There aren’t enough usable breakfast, lunch and dinner recipes to make a complete week."
            return
        }
        draft = proposed
    }

    private func planningRecipe(_ recipe: Recipe) -> PlanningRecipe? {
        guard let id = recipe.id, let name = recipe.name else { return nil }
        let tagSet = Set(recipe.tagList.map { $0.lowercased() })
        var mealTypes = Set(MealType.allCases.filter { tagSet.contains($0.rawValue.lowercased()) })
        if mealTypes.isEmpty { mealTypes = [.dinner] }
        let calculation = NutritionCalculator.calculate(recipe: recipe)
        let calories = calculation.isComplete
            ? calculation.perServing.calories
            : (recipe.hasCalories ? recipe.caloriesPerServing : nil)
        let protein = calculation.isComplete
            ? calculation.perServing.proteinGrams
            : (recipe.hasProtein ? recipe.proteinPerServing : nil)
        return PlanningRecipe(
            id: id,
            name: name,
            mealTypes: mealTypes,
            defaultServings: max(recipe.defaultServings, 1),
            caloriesPerServing: calories,
            proteinPerServing: protein,
            nutritionIsComplete: calculation.isComplete,
            isOfficeFriendly: tagSet.contains("office") || tagSet.contains("no cook"),
            isBatchCook: recipe.defaultServings >= 4,
            isNew: false
        )
    }

    private func entries(on date: Date, in draft: WeeklyPlanDraft) -> [WeeklyPlanDraftEntry] {
        draft.entries
            .filter { WeekCalendar.calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    private func dailyCalories(on date: Date, in draft: WeeklyPlanDraft) -> Double? {
        let meals = entries(on: date, in: draft)
        let values = meals.compactMap { planningRecipes[$0.recipeID]?.caloriesPerServing }
        guard values.count == meals.count else { return nil }
        return values.reduce(0, +)
    }

    private func replace(_ entry: WeeklyPlanDraftEntry, with recipe: PlanningRecipe) {
        guard var updatedDraft = draft,
              let index = updatedDraft.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        updatedDraft.entries[index] = WeeklyPlanDraftEntry(
            id: entry.id,
            date: entry.date,
            mealType: entry.mealType,
            recipeID: recipe.id,
            recipeName: recipe.name,
            isNewRecipe: recipe.isNew,
            isLeftover: false,
            leftoverSourceID: nil,
            servingsPrepared: recipe.defaultServings,
            servingsEaten: entry.mealType == .dinner ? min(2, recipe.defaultServings) : 1,
            isOfficeDay: entry.isOfficeDay
        )
        for leftoverIndex in updatedDraft.entries.indices
        where updatedDraft.entries[leftoverIndex].leftoverSourceID == entry.id {
            let leftover = updatedDraft.entries[leftoverIndex]
            updatedDraft.entries[leftoverIndex] = WeeklyPlanDraftEntry(
                id: leftover.id,
                date: leftover.date,
                mealType: leftover.mealType,
                recipeID: recipe.id,
                recipeName: recipe.name,
                isNewRecipe: recipe.isNew,
                isLeftover: true,
                leftoverSourceID: entry.id,
                servingsPrepared: 0,
                servingsEaten: min(2, max(recipe.defaultServings - 2, 1)),
                isOfficeDay: leftover.isOfficeDay
            )
        }
        draft = updatedDraft
    }

    private func requestFreshDinner() {
        isSuggesting = true
        Task {
            do {
                let suggestion = try await FreshRecipeSuggester.suggestDinner(
                    variation: recipes.filter(\.isGenerated).count + newRecipeDrafts.count
                )
                await MainActor.run {
                    newRecipeDrafts[suggestion.id] = suggestion
                    featuredSuggestionID = suggestion.id
                    isSuggesting = false
                    rebuildPlan(avoidingCurrentPlan: true)
                }
            } catch {
                await MainActor.run {
                    isSuggesting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func attemptSave() {
        let hasExistingPlan = historyEntries.contains { entry in
            guard let date = entry.date else { return false }
            return date >= weekStart && date < WeekCalendar.weekEnd(containing: weekStart)
        }
        if hasExistingPlan {
            showingReplaceConfirmation = true
        } else {
            savePlan()
        }
    }

    private func savePlan() {
        guard let draft else { return }
        do {
            _ = try PlanPersistenceService.save(
                draft: draft,
                newRecipeDrafts: newRecipeDrafts,
                household: household,
                in: context
            )
            onSaved()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlanMealRow: View {
    let entry: WeeklyPlanDraftEntry
    let recipe: PlanningRecipe?
    let canSwap: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.mealType.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.isLeftover ? "Leftover \(entry.recipeName)" : entry.recipeName)
                        .foregroundStyle(.primary)
                    if entry.isNewRecipe && !entry.isLeftover {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 10) {
                    if let calories = recipe?.caloriesPerServing {
                        Text("~\(QuantityText.format(calories)) kcal per serving")
                    }
                    if let protein = recipe?.proteinPerServing {
                        Text("~\(QuantityText.format(protein)) g protein")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if recipe?.nutritionIsComplete == false {
                    Text("Stored estimate — add pack values in the recipe to improve it")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if entry.isLeftover {
                    Text("Uses \(QuantityText.format(entry.servingsEaten)) saved servings — nothing cooked or bought twice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if entry.servingsPrepared > entry.servingsEaten {
                    Text("Cook \(QuantityText.format(entry.servingsPrepared)) servings · eat \(QuantityText.format(entry.servingsEaten)) now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if canSwap {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct DraftRecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let mealType: MealType
    let currentRecipeID: UUID
    let recipes: [PlanningRecipe]
    let onSelect: (PlanningRecipe) -> Void

    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                Button {
                    onSelect(recipe)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .foregroundStyle(.primary)
                            HStack(spacing: 10) {
                                if let calories = recipe.caloriesPerServing {
                                    Text("~\(QuantityText.format(calories)) kcal")
                                }
                                if let protein = recipe.proteinPerServing {
                                    Text("~\(QuantityText.format(protein)) g protein")
                                }
                                if !recipe.nutritionIsComplete {
                                    Text("estimate")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if recipe.id == currentRecipeID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Choose \(mealType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
