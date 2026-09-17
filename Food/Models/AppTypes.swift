import Foundation

enum MealType: String, CaseIterable, Hashable, Identifiable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"

    var id: String { rawValue }
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum ShoppingCategoryName: String, CaseIterable, Identifiable {
    case dairy = "Dairy"
    case fridge = "Fridge"
    case fruitAndVeg = "Fruit & Veg"
    case freezer = "Freezer"
    case cupboard = "Cupboard"
    case bread = "Bread"
    case cleaning = "Cleaning"
    case theBoys = "The Boys"
    case house = "House"
    case drinks = "Drinks"

    var id: String { rawValue }
    var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func orderedName(_ name: String) -> Int {
        Self(rawValue: name)?.sortOrder ?? Self.allCases.count
    }
}

enum WeekCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    static func weekStart(containing date: Date = .now) -> Date {
        let calendar = calendar
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
    }

    static func weekEnd(containing date: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart(containing: date)) ?? date
    }

    static func day(_ offset: Int, fromWeekContaining date: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: offset, to: weekStart(containing: date)) ?? date
    }
}

enum QuantityText {
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0001 { return String(Int(rounded)) }
        if value < 5, abs(value * 4 - (value * 4).rounded()) < 0.0001 {
            let whole = Int(value.rounded(.towardZero))
            let fraction = value - Double(whole)
            let suffix: String
            switch Int((fraction * 4).rounded()) {
            case 1: suffix = "¼"
            case 2: suffix = "½"
            case 3: suffix = "¾"
            default: suffix = ""
            }
            return whole == 0 ? suffix : "\(whole)\(suffix)"
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func ingredient(amount: Double?, unit: String?, name: String, note: String? = nil) -> String {
        var components: [String] = []
        if let amount { components.append(format(amount)) }
        if let unit, !unit.isEmpty { components.append(unit) }
        components.append(name)
        if let note, !note.isEmpty { components.append("— \(note)") }
        return components.joined(separator: " ")
    }
}
