import CoreData
import XCTest
@testable import Food

final class SeedDataTests: XCTestCase {
    private var persistence: PersistenceController!
    private var household: Household!

    override func setUpWithError() throws {
        persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        waitForPersistence()
        household = try persistence.createHousehold(named: "The Scudders")
    }

    override func tearDown() {
        household = nil
        persistence = nil
    }

    func testSeedOnlyRunsOnce() throws {
        let context = persistence.container.viewContext
        let recipeCount = try context.count(for: Recipe.fetchRequest())
        let entryCount = try context.count(for: MealPlanEntry.fetchRequest())
        let categoryCount = try context.count(for: ShoppingCategory.fetchRequest())

        XCTAssertFalse(try SeedData.seedIfNeeded(household: household, in: context))
        XCTAssertEqual(try context.count(for: Recipe.fetchRequest()), recipeCount)
        XCTAssertEqual(try context.count(for: MealPlanEntry.fetchRequest()), entryCount)
        XCTAssertEqual(try context.count(for: ShoppingCategory.fetchRequest()), categoryCount)
        XCTAssertEqual(recipeCount, 14)
        XCTAssertEqual(entryCount, 21)
        XCTAssertEqual(categoryCount, 10)
    }

    func testLeftoversReferenceTheirOriginalRecipes() throws {
        let request = MealPlanEntry.fetchRequest()
        request.predicate = NSPredicate(format: "isLeftover == YES")
        let leftovers = try persistence.container.viewContext.fetch(request)

        XCTAssertEqual(leftovers.count, 2)
        XCTAssertEqual(
            Set(leftovers.compactMap { $0.recipe?.name }),
            Set(["Lentil + TVP Bolognese", "Bean + TVP Chilli with Rice"])
        )
    }

    func testDefaultPlanHasThreeMealsForEveryDayOfCurrentWeek() throws {
        let entries = try persistence.container.viewContext.fetch(MealPlanEntry.fetchRequest())
        let weekStart = WeekCalendar.weekStart()

        XCTAssertEqual(entries.count, 21)
        for offset in 0..<7 {
            let date = WeekCalendar.calendar.date(byAdding: .day, value: offset, to: weekStart)!
            let dayEntries = entries.filter {
                guard let entryDate = $0.date else { return false }
                return WeekCalendar.calendar.isDate(entryDate, inSameDayAs: date)
            }
            XCTAssertEqual(dayEntries.count, 3)
            XCTAssertEqual(Set(dayEntries.compactMap(\.mealType)), Set(MealType.allCases.map(\.rawValue)))
        }
    }

    func testTuesdayAndWednesdayAreOfficeDays() throws {
        let entries = try persistence.container.viewContext.fetch(MealPlanEntry.fetchRequest())
        let start = WeekCalendar.weekStart()

        for entry in entries {
            let offset = WeekCalendar.calendar.dateComponents(
                [.day],
                from: start,
                to: entry.date ?? start
            ).day
            XCTAssertEqual(entry.isOfficeDay, offset == 1 || offset == 2)
        }
    }

    func testShoppingIngredientsSkipLeftoversAlreadyCoveredByBatchCook() throws {
        let entries = try persistence.container.viewContext.fetch(MealPlanEntry.fetchRequest())
        let planned = ShoppingListAggregator.ingredients(from: entries)
        let pasta = planned.filter { $0.name == "wholewheat pasta" }

        XCTAssertEqual(pasta.count, 1)
        XCTAssertEqual(pasta.first?.amount, 300)
    }

    private func waitForPersistence(file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while !persistence.isReady && persistence.loadErrorMessage == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(persistence.isReady, persistence.loadErrorMessage ?? "Store did not load", file: file, line: line)
    }
}
