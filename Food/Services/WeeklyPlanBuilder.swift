import Foundation

struct MealCalorieBudget: Equatable, Sendable {
    let dailyTarget: Double
    let unplannedReserve: Double

    var plannedCalories: Double {
        max(dailyTarget - unplannedReserve, 0)
    }

    func target(for mealType: MealType) -> Double {
        let share: Double
        switch mealType {
        case .breakfast: share = 0.25
        case .lunch: share = 0.30
        case .dinner: share = 0.45
        }
        return plannedCalories * share
    }

    var ranges: [MealType: ClosedRange<Double>] {
        Dictionary(uniqueKeysWithValues: MealType.allCases.map { mealType in
            let mealTarget = target(for: mealType)
            return (mealType, (mealTarget * 0.75)...mealTarget)
        })
    }
}

struct PlanningRecipe: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let mealTypes: Set<MealType>
    let defaultServings: Double
    let caloriesPerServing: Double?
    let proteinPerServing: Double?
    let isOfficeFriendly: Bool
    let isBatchCook: Bool
    let isNew: Bool
}

struct PlanningHistoryEntry: Equatable, Sendable {
    let date: Date
    let mealType: MealType
    let recipeID: UUID
}

struct WeeklyPlanPreferences: Equatable, Sendable {
    var officeWeekdays: Set<Int>
    var batchCookingWeekdays: Set<Int>
    var calorieRanges: [MealType: ClosedRange<Double>]
    var recentlyUsedRecipeIDs: Set<UUID>

    init(
        officeWeekdays: Set<Int> = [],
        batchCookingWeekdays: Set<Int> = [],
        calorieRanges: [MealType: ClosedRange<Double>] = [:],
        recentlyUsedRecipeIDs: Set<UUID> = []
    ) {
        self.officeWeekdays = officeWeekdays
        self.batchCookingWeekdays = batchCookingWeekdays
        self.calorieRanges = calorieRanges
        self.recentlyUsedRecipeIDs = recentlyUsedRecipeIDs
    }
}

struct WeeklyPlanDraftEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let mealType: MealType
    let recipeID: UUID
    let recipeName: String
    let isNewRecipe: Bool
    let isLeftover: Bool
    let leftoverSourceID: UUID?
    let servingsPrepared: Double
    let servingsEaten: Double
    let isOfficeDay: Bool
}

struct WeeklyPlanDraft: Equatable, Sendable {
    let weekStart: Date
    var entries: [WeeklyPlanDraftEntry]
}

enum WeeklyPlanBuilder {
    static func build(
        weekStarting weekStart: Date,
        recipes: [PlanningRecipe],
        history: [PlanningHistoryEntry],
        preferences: WeeklyPlanPreferences,
        calendar: Calendar = WeekCalendar.calendar
    ) -> WeeklyPlanDraft {
        var entries: [WeeklyPlanDraftEntry] = []
        var usage: [UUID: Int] = [:]
        var leftoversByDay: [Date: WeeklyPlanDraftEntry] = [:]

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                continue
            }
            let isOfficeDay = preferences.officeWeekdays.contains(calendar.component(.weekday, from: date))
            let isBatchCookingDay = preferences.batchCookingWeekdays.contains(
                calendar.component(.weekday, from: date)
            )

            for mealType in MealType.allCases {
                if mealType == .lunch,
                   let source = leftoversByDay[calendar.startOfDay(for: date)] {
                    let remaining = max(source.servingsPrepared - source.servingsEaten, 1)
                    entries.append(WeeklyPlanDraftEntry(
                        id: UUID(),
                        date: date,
                        mealType: .lunch,
                        recipeID: source.recipeID,
                        recipeName: source.recipeName,
                        isNewRecipe: source.isNewRecipe,
                        isLeftover: true,
                        leftoverSourceID: source.id,
                        servingsPrepared: 0,
                        servingsEaten: remaining,
                        isOfficeDay: isOfficeDay
                    ))
                    continue
                }

                let candidates = candidates(
                    for: mealType,
                    officeDay: isOfficeDay,
                    batchCookingDay: isBatchCookingDay,
                    recipes: recipes,
                    preferences: preferences
                )
                guard let recipe = choose(
                    candidates,
                    usage: usage,
                    history: history,
                    recentlyUsedRecipeIDs: preferences.recentlyUsedRecipeIDs,
                    calorieRange: preferences.calorieRanges[mealType]
                ) else { continue }
                usage[recipe.id, default: 0] += 1

                let entry = WeeklyPlanDraftEntry(
                    id: UUID(),
                    date: date,
                    mealType: mealType,
                    recipeID: recipe.id,
                    recipeName: recipe.name,
                    isNewRecipe: recipe.isNew,
                    isLeftover: false,
                    leftoverSourceID: nil,
                    servingsPrepared: recipe.defaultServings,
                    servingsEaten: mealType == .dinner ? min(2, recipe.defaultServings) : 1,
                    isOfficeDay: isOfficeDay
                )
                entries.append(entry)

                if mealType == .dinner,
                   recipe.isBatchCook,
                   recipe.defaultServings > entry.servingsEaten,
                   let leftoverDate = calendar.date(byAdding: .day, value: 1, to: date) {
                    leftoversByDay[calendar.startOfDay(for: leftoverDate)] = entry
                }
            }
        }

        return WeeklyPlanDraft(weekStart: weekStart, entries: entries)
    }

    private static func candidates(
        for mealType: MealType,
        officeDay: Bool,
        batchCookingDay: Bool,
        recipes: [PlanningRecipe],
        preferences: WeeklyPlanPreferences
    ) -> [PlanningRecipe] {
        var matches = recipes.filter { $0.mealTypes.contains(mealType) }
        if officeDay, mealType != .dinner {
            let portable = matches.filter(\.isOfficeFriendly)
            if !portable.isEmpty { matches = portable }
        }
        if mealType == .dinner {
            let preferred = matches.filter { $0.isBatchCook == batchCookingDay }
            if !preferred.isEmpty { matches = preferred }
        }
        if let range = preferences.calorieRanges[mealType] {
            let withinRange = matches.filter {
                guard let calories = $0.caloriesPerServing else { return false }
                return range.contains(calories)
            }
            if !withinRange.isEmpty { matches = withinRange }
        }
        return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func choose(
        _ candidates: [PlanningRecipe],
        usage: [UUID: Int],
        history: [PlanningHistoryEntry],
        recentlyUsedRecipeIDs: Set<UUID>,
        calorieRange: ClosedRange<Double>?
    ) -> PlanningRecipe? {
        candidates.min { lhs, rhs in
            let lhsScore = (
                usage[lhs.id, default: 0],
                recentlyUsedRecipeIDs.contains(lhs.id) ? 1 : 0,
                calorieDistance(lhs, from: calorieRange),
                lhs.isNew ? 0 : 1,
                mostRecentUse(lhs.id, in: history)
            )
            let rhsScore = (
                usage[rhs.id, default: 0],
                recentlyUsedRecipeIDs.contains(rhs.id) ? 1 : 0,
                calorieDistance(rhs, from: calorieRange),
                rhs.isNew ? 0 : 1,
                mostRecentUse(rhs.id, in: history)
            )
            if lhsScore.0 != rhsScore.0 { return lhsScore.0 < rhsScore.0 }
            if lhsScore.1 != rhsScore.1 { return lhsScore.1 < rhsScore.1 }
            if lhsScore.2 != rhsScore.2 { return lhsScore.2 < rhsScore.2 }
            if lhsScore.3 != rhsScore.3 { return lhsScore.3 < rhsScore.3 }
            if lhsScore.4 != rhsScore.4 { return lhsScore.4 < rhsScore.4 }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func calorieDistance(
        _ recipe: PlanningRecipe,
        from range: ClosedRange<Double>?
    ) -> Double {
        guard let calories = recipe.caloriesPerServing, let range else { return .greatestFiniteMagnitude }
        let target = range.upperBound
        return abs(calories - target)
    }

    private static func mostRecentUse(_ recipeID: UUID, in history: [PlanningHistoryEntry]) -> Date {
        history.lazy.filter { $0.recipeID == recipeID }.map(\.date).max() ?? .distantPast
    }
}
