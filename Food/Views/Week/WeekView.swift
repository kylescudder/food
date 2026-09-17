import CoreData
import SwiftUI

struct WeekView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @FetchRequest private var entries: FetchedResults<MealPlanEntry>
    @State private var entryToSwap: MealPlanEntry?
    @State private var showingHousehold = false
    @State private var saveError: String?

    private let weekStart = WeekCalendar.weekStart()

    init(household: Household) {
        self.household = household
        let start = WeekCalendar.weekStart()
        let end = WeekCalendar.weekEnd()
        _entries = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \MealPlanEntry.date, ascending: true),
                NSSortDescriptor(keyPath: \MealPlanEntry.mealType, ascending: true)
            ],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "household == %@", household),
                NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
            ]),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<7, id: \.self) { offset in
                    let date = WeekCalendar.calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: weekStart
                    ) ?? weekStart
                    let meals = entriesForDay(date)

                    Section {
                        ForEach(meals, id: \.objectID) { entry in
                            if let recipe = entry.recipe {
                                NavigationLink {
                                    RecipeDetailView(recipe: recipe)
                                } label: {
                                    MealRow(entry: entry)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        entryToSwap = entry
                                    } label: {
                                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .tint(.green)
                                }
                            } else {
                                MealRow(entry: entry)
                            }
                        }
                    } header: {
                        DayHeader(date: date, isOfficeDay: meals.contains(where: \.isOfficeDay))
                    }
                }
            }
            .navigationTitle("This Week")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHousehold = true
                    } label: {
                        Label("Household", systemImage: "person.2")
                    }
                }
            }
            .sheet(item: $entryToSwap) { entry in
                SwapRecipeView(household: household, entry: entry) { recipe in
                    entry.recipe = recipe
                    entry.displayNameOverride = nil
                    entry.isLeftover = false
                    entry.plannedServings = recipe.defaultServings
                    do {
                        try persistence.saveViewContext()
                    } catch {
                        context.rollback()
                        saveError = error.localizedDescription
                    }
                    entryToSwap = nil
                }
            }
            .sheet(isPresented: $showingHousehold) {
                HouseholdSettingsView(household: household)
                    .environmentObject(persistence)
            }
            .alert("Couldn’t Save Meal", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
    }

    private func entriesForDay(_ date: Date) -> [MealPlanEntry] {
        entries
            .filter { entry in
                guard let entryDate = entry.date else { return false }
                return WeekCalendar.calendar.isDate(entryDate, inSameDayAs: date)
            }
            .sorted {
                let lhs = MealType(rawValue: $0.mealType ?? "")?.sortOrder ?? 99
                let rhs = MealType(rawValue: $1.mealType ?? "")?.sortOrder ?? 99
                return lhs < rhs
            }
    }
}

private struct DayHeader: View {
    let date: Date
    let isOfficeDay: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.wide)).uppercased())
            if isOfficeDay {
                Text("·")
                Label("OFFICE", systemImage: "building.2")
                    .labelStyle(.titleAndIcon)
            }
            Spacer()
            Text(date.formatted(.dateTime.day()))
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
    }
}

private struct MealRow: View {
    @ObservedObject var entry: MealPlanEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.mealType ?? "Meal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(entry.displayName)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct SwapRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var recipes: FetchedResults<Recipe>
    @ObservedObject var entry: MealPlanEntry
    let onSelect: (Recipe) -> Void

    init(household: Household, entry: MealPlanEntry, onSelect: @escaping (Recipe) -> Void) {
        self.entry = entry
        self.onSelect = onSelect
        _recipes = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List(recipes, id: \.objectID) { recipe in
                Button {
                    onSelect(recipe)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.name ?? "Recipe")
                                .foregroundStyle(.primary)
                            Text("Serves \(QuantityText.format(recipe.defaultServings))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if recipe == entry.recipe {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Swap \(entry.mealType ?? "Meal")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
