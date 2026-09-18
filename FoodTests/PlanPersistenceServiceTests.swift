import CoreData
import XCTest
@testable import Food

final class PlanPersistenceServiceTests: XCTestCase {
    private var persistence: PersistenceController!
    private var household: Household!

    override func setUpWithError() throws {
        persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        let deadline = Date().addingTimeInterval(2)
        while !persistence.isReady && persistence.loadErrorMessage == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(persistence.isReady, persistence.loadErrorMessage ?? "Store did not load")
        household = try persistence.createHousehold(named: "The Scudders")
    }

    override func tearDown() {
        household = nil
        persistence = nil
    }

    func testSavingDraftCreatesRecipeAndLinksLeftoverWithoutDuplicatingTheWeek() throws {
        let context = persistence.container.viewContext
        let weekStart = WeekCalendar.calendar.date(
            byAdding: .day,
            value: 7,
            to: WeekCalendar.weekStart()
        )!
        let suggestion = RecipeSuggestionCatalog.suggestions[0]
        let sourceID = UUID()
        let source = WeeklyPlanDraftEntry(
            id: sourceID,
            date: weekStart,
            mealType: .dinner,
            recipeID: suggestion.id,
            recipeName: suggestion.name,
            isNewRecipe: true,
            isLeftover: false,
            leftoverSourceID: nil,
            servingsPrepared: 4,
            servingsEaten: 2,
            isOfficeDay: false
        )
        let leftover = WeeklyPlanDraftEntry(
            id: UUID(),
            date: WeekCalendar.calendar.date(byAdding: .day, value: 1, to: weekStart)!,
            mealType: .lunch,
            recipeID: suggestion.id,
            recipeName: suggestion.name,
            isNewRecipe: true,
            isLeftover: true,
            leftoverSourceID: sourceID,
            servingsPrepared: 0,
            servingsEaten: 2,
            isOfficeDay: true
        )
        var draftEntries: [WeeklyPlanDraftEntry] = [source, leftover]
        for dayOffset in 0..<7 {
            let date = WeekCalendar.calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            for mealType in MealType.allCases {
                let isSource = dayOffset == 0 && mealType == .dinner
                let isLeftover = dayOffset == 1 && mealType == .lunch
                guard !isSource && !isLeftover else { continue }
                draftEntries.append(WeeklyPlanDraftEntry(
                    id: UUID(),
                    date: date,
                    mealType: mealType,
                    recipeID: suggestion.id,
                    recipeName: suggestion.name,
                    isNewRecipe: true,
                    isLeftover: false,
                    leftoverSourceID: nil,
                    servingsPrepared: suggestion.defaultServings,
                    servingsEaten: mealType == .dinner ? 2 : 1,
                    isOfficeDay: dayOffset == 1 || dayOffset == 2
                ))
            }
        }
        let draft = WeeklyPlanDraft(weekStart: weekStart, entries: draftEntries)

        let firstSave = try PlanPersistenceService.save(
            draft: draft,
            newRecipeDrafts: [suggestion.id: suggestion],
            household: household,
            in: context
        )
        let secondSave = try PlanPersistenceService.save(
            draft: draft,
            newRecipeDrafts: [suggestion.id: suggestion],
            household: household,
            in: context
        )

        XCTAssertEqual(firstSave.count, 21)
        XCTAssertEqual(secondSave.count, 21)
        XCTAssertEqual(try entries(in: weekStart, context: context).count, 21)
        XCTAssertEqual(try recipes(with: suggestion.id, context: context).count, 1)
        let savedLeftover = try XCTUnwrap(secondSave.first(where: \.isLeftover))
        XCTAssertEqual(savedLeftover.leftoverSource?.id, sourceID)
        XCTAssertEqual(savedLeftover.leftoverSource?.servingsPrepared, 4)
        XCTAssertTrue(savedLeftover.isOfficeDay)
        XCTAssertTrue(NutritionCalculator.calculate(recipe: savedLeftover.recipe!).isComplete)
    }

    private func entries(
        in weekStart: Date,
        context: NSManagedObjectContext
    ) throws -> [MealPlanEntry] {
        let request = MealPlanEntry.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "household == %@", household),
            NSPredicate(
                format: "date >= %@ AND date < %@",
                weekStart as NSDate,
                WeekCalendar.weekEnd(containing: weekStart) as NSDate
            )
        ])
        return try context.fetch(request)
    }

    private func recipes(
        with id: UUID,
        context: NSManagedObjectContext
    ) throws -> [Recipe] {
        let request = Recipe.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "household == %@", household),
            NSPredicate(format: "id == %@", id as NSUUID)
        ])
        return try context.fetch(request)
    }
}
