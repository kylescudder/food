import XCTest
@testable import Food

final class WeeklyPlanBuilderTests: XCTestCase {
    func testCalorieBudgetLeavesRoomForUnplannedFoodAndAllocatesTheRest() {
        let budget = MealCalorieBudget(dailyTarget: 2_000, unplannedReserve: 200)

        XCTAssertEqual(budget.plannedCalories, 1_800)
        XCTAssertEqual(budget.target(for: .breakfast), 450)
        XCTAssertEqual(budget.target(for: .lunch), 540)
        XCTAssertEqual(budget.target(for: .dinner), 810)
        XCTAssertEqual(budget.ranges.values.map(\.lowerBound).reduce(0, +), 1_350)
        XCTAssertEqual(budget.ranges.values.map(\.upperBound).reduce(0, +), 1_800)
    }

    func testBuildsCompleteWeekAndUsesPortableBreakfastOnOfficeDays() throws {
        let calendar = makeCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21
        )))
        let regularBreakfast = recipe("Porridge", mealType: .breakfast)
        let officeBreakfast = recipe("Overnight Oats", mealType: .breakfast, officeFriendly: true)
        let lunch = recipe("Chickpea Wrap", mealType: .lunch, officeFriendly: true)
        let dinner = recipe("Tofu Curry", mealType: .dinner)

        let plan = WeeklyPlanBuilder.build(
            weekStarting: monday,
            recipes: [regularBreakfast, officeBreakfast, lunch, dinner],
            history: [],
            preferences: WeeklyPlanPreferences(officeWeekdays: [3, 4]),
            calendar: calendar
        )

        XCTAssertEqual(plan.entries.count, 21)
        let tuesdayBreakfast = try XCTUnwrap(plan.entries.first {
            calendar.isDate($0.date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: monday)!)
                && $0.mealType == .breakfast
        })
        XCTAssertEqual(tuesdayBreakfast.recipeID, officeBreakfast.id)
        XCTAssertTrue(tuesdayBreakfast.isOfficeDay)
    }

    func testFreshRecipesArePreferredButDoNotRepeatEveryDay() throws {
        let calendar = makeCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21
        )))
        let freshBreakfast = PlanningRecipe(
            id: UUID(),
            name: "Fresh Breakfast",
            mealTypes: [.breakfast],
            defaultServings: 1,
            caloriesPerServing: 450,
            proteinPerServing: 25,
            isOfficeFriendly: true,
            isBatchCook: false,
            isNew: true
        )
        let existingBreakfast = recipe("Existing Breakfast", mealType: .breakfast)

        let plan = WeeklyPlanBuilder.build(
            weekStarting: monday,
            recipes: [
                freshBreakfast,
                existingBreakfast,
                recipe("Lunch", mealType: .lunch),
                recipe("Dinner", mealType: .dinner)
            ],
            history: [],
            preferences: WeeklyPlanPreferences(),
            calendar: calendar
        )
        let breakfasts = plan.entries.filter { $0.mealType == .breakfast }

        XCTAssertEqual(breakfasts.first?.recipeID, freshBreakfast.id)
        XCTAssertTrue(breakfasts.contains { $0.recipeID == existingBreakfast.id })
    }

    func testChoosesTheMealClosestToKyleBudgetWhenBothAreSuitable() throws {
        let calendar = makeCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21
        )))
        let lowerDinner = recipe("Lower Dinner", mealType: .dinner, calories: 600)
        let closerDinner = recipe("Closer Dinner", mealType: .dinner, calories: 700)

        let plan = WeeklyPlanBuilder.build(
            weekStarting: monday,
            recipes: [
                recipe("Breakfast", mealType: .breakfast),
                recipe("Lunch", mealType: .lunch),
                lowerDinner,
                closerDinner
            ],
            history: [],
            preferences: WeeklyPlanPreferences(calorieRanges: [.dinner: 500...700]),
            calendar: calendar
        )
        let mondayDinner = try XCTUnwrap(plan.entries.first {
            calendar.isDate($0.date, inSameDayAs: monday) && $0.mealType == .dinner
        })

        XCTAssertEqual(mondayDinner.recipeID, closerDinner.id)
    }

    func testBatchDinnerCreatesLinkedLeftoverLunchWithoutPreparingItAgain() throws {
        let calendar = makeCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21
        )))
        let breakfast = recipe("Porridge", mealType: .breakfast)
        let lunch = recipe("Wrap", mealType: .lunch)
        let quickDinner = recipe("Quick Curry", mealType: .dinner)
        let batchDinner = recipe(
            "Lentil Bolognese",
            mealType: .dinner,
            defaultServings: 4,
            isBatchCook: true
        )

        let plan = WeeklyPlanBuilder.build(
            weekStarting: monday,
            recipes: [breakfast, lunch, quickDinner, batchDinner],
            history: [],
            preferences: WeeklyPlanPreferences(batchCookingWeekdays: [3]),
            calendar: calendar
        )
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: monday))
        let source = try XCTUnwrap(plan.entries.first {
            calendar.isDate($0.date, inSameDayAs: tuesday) && $0.mealType == .dinner
        })
        let leftover = try XCTUnwrap(plan.entries.first {
            calendar.isDate($0.date, inSameDayAs: wednesday) && $0.mealType == .lunch
        })

        XCTAssertEqual(source.recipeID, batchDinner.id)
        XCTAssertEqual(source.servingsPrepared, 4)
        XCTAssertEqual(source.servingsEaten, 2)
        XCTAssertTrue(leftover.isLeftover)
        XCTAssertEqual(leftover.recipeID, batchDinner.id)
        XCTAssertEqual(leftover.leftoverSourceID, source.id)
        XCTAssertEqual(leftover.servingsPrepared, 0)
        XCTAssertEqual(leftover.servingsEaten, 2)
    }

    func testAvoidsRecentlyUsedRecipeWhenAnotherSuitableMealExists() throws {
        let calendar = makeCalendar()
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21
        )))
        let recentDinner = recipe("Recent Dinner", mealType: .dinner)
        let freshDinner = recipe("Fresh Dinner", mealType: .dinner)

        let plan = WeeklyPlanBuilder.build(
            weekStarting: monday,
            recipes: [
                recipe("Breakfast", mealType: .breakfast),
                recipe("Lunch", mealType: .lunch),
                recentDinner,
                freshDinner
            ],
            history: [],
            preferences: WeeklyPlanPreferences(recentlyUsedRecipeIDs: [recentDinner.id]),
            calendar: calendar
        )
        let mondayDinner = try XCTUnwrap(plan.entries.first {
            calendar.isDate($0.date, inSameDayAs: monday) && $0.mealType == .dinner
        })

        XCTAssertEqual(mondayDinner.recipeID, freshDinner.id)
    }

    private func recipe(
        _ name: String,
        mealType: MealType,
        officeFriendly: Bool = false,
        defaultServings: Double? = nil,
        isBatchCook: Bool = false,
        calories: Double = 500
    ) -> PlanningRecipe {
        PlanningRecipe(
            id: UUID(),
            name: name,
            mealTypes: [mealType],
            defaultServings: defaultServings ?? (mealType == .dinner ? 2 : 1),
            caloriesPerServing: calories,
            proteinPerServing: 30,
            isOfficeFriendly: officeFriendly,
            isBatchCook: isBatchCook,
            isNew: false
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }
}
