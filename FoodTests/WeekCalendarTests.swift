import XCTest
@testable import Food

final class WeekCalendarTests: XCTestCase {
    func testPlanningFromPopulatedCurrentWeekTargetsNextWeek() throws {
        let today = try XCTUnwrap(WeekCalendar.calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 18
        )))
        let currentWeek = WeekCalendar.weekStart(containing: today)
        let expected = try XCTUnwrap(WeekCalendar.calendar.date(
            byAdding: .day,
            value: 7,
            to: currentWeek
        ))

        let target = WeekCalendar.planningTarget(
            selectedWeek: currentWeek,
            hasPlannedMeals: true,
            relativeTo: today
        )

        XCTAssertEqual(target, expected)
    }

    func testPlanningAnEmptySelectedWeekKeepsThatWeek() throws {
        let today = try XCTUnwrap(WeekCalendar.calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 18
        )))
        let nextWeek = try XCTUnwrap(WeekCalendar.calendar.date(
            byAdding: .day,
            value: 7,
            to: WeekCalendar.weekStart(containing: today)
        ))

        let target = WeekCalendar.planningTarget(
            selectedWeek: nextWeek,
            hasPlannedMeals: false,
            relativeTo: today
        )

        XCTAssertEqual(target, nextWeek)
    }
}
