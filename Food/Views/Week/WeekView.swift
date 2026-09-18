import CoreData
import SwiftUI

struct WeekView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @FetchRequest private var entries: FetchedResults<MealPlanEntry>
    @State private var entryToSwap: MealPlanEntry?
    @State private var showingHousehold = false
    @State private var showingPlanner = false
    @State private var showingShoppingGenerator = false
    @State private var pendingShoppingWeek: Date?
    @State private var selectedWeekStart = WeekCalendar.weekStart()
    @State private var saveError: String?

    init(household: Household) {
        self.household = household
        _entries = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \MealPlanEntry.date, ascending: true),
                NSSortDescriptor(keyPath: \MealPlanEntry.mealType, ascending: true)
            ],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weekNavigator
                }

                if entriesForSelectedWeek.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Planned", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Build a fresh week from your recipes and a few new ideas.")
                    } actions: {
                        Button("Plan This Week") { showingPlanner = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(0..<7, id: \.self) { offset in
                    let date = WeekCalendar.calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: selectedWeekStart
                    ) ?? selectedWeekStart
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
            .navigationTitle(weekTitle)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingPlanner = true
                    } label: {
                        Label("Plan Week", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showingHousehold = true
                    } label: {
                        Label("Household", systemImage: "person.2")
                    }
                }
            }
            .sheet(item: $entryToSwap) { entry in
                SwapRecipeView(household: household, entry: entry) { recipe in
                    let originalLeftoverSource = entry.leftoverSource
                    let dependentLeftovers = entry.leftoverMeals as? Set<MealPlanEntry> ?? []
                    let servingsNeeded = entry.effectiveServingsEaten
                        + dependentLeftovers.map(\.effectiveServingsEaten).reduce(0, +)
                    entry.recipe = recipe
                    entry.displayNameOverride = nil
                    entry.isLeftover = false
                    entry.leftoverSource = nil
                    entry.servingsPrepared = max(recipe.defaultServings, servingsNeeded)
                    entry.plannedServings = entry.servingsPrepared
                    entry.servingsEaten = entry.mealType == MealType.dinner.rawValue
                        ? min(2, recipe.defaultServings)
                        : 1
                    if let originalLeftoverSource {
                        let otherLeftovers = (originalLeftoverSource.leftoverMeals as? Set<MealPlanEntry> ?? [])
                            .filter { $0.objectID != entry.objectID }
                        let originalServingsNeeded = originalLeftoverSource.effectiveServingsEaten
                            + otherLeftovers.map(\.effectiveServingsEaten).reduce(0, +)
                        originalLeftoverSource.servingsPrepared = max(originalServingsNeeded, 1)
                        originalLeftoverSource.plannedServings = originalLeftoverSource.servingsPrepared
                    }
                    for leftover in dependentLeftovers {
                        leftover.recipe = recipe
                        leftover.displayNameOverride = nil
                    }
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
            .sheet(isPresented: $showingPlanner) {
                PlanWeekView(household: household, weekStart: selectedWeekStart) {
                    pendingShoppingWeek = selectedWeekStart
                }
                .environmentObject(persistence)
            }
            .sheet(isPresented: $showingShoppingGenerator) {
                GenerateShoppingListView(
                    household: household,
                    initialWeekStart: pendingShoppingWeek ?? selectedWeekStart
                )
                .environmentObject(persistence)
            }
            .onChange(of: showingPlanner) { _, isShowing in
                if !isShowing, pendingShoppingWeek != nil {
                    showingShoppingGenerator = true
                }
            }
            .onChange(of: showingShoppingGenerator) { _, isShowing in
                if !isShowing { pendingShoppingWeek = nil }
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

    private var entriesForSelectedWeek: [MealPlanEntry] {
        let end = WeekCalendar.weekEnd(containing: selectedWeekStart)
        return entries.filter {
            guard let date = $0.date else { return false }
            return date >= selectedWeekStart && date < end
        }
    }

    private var weekTitle: String {
        let current = WeekCalendar.weekStart()
        if WeekCalendar.calendar.isDate(selectedWeekStart, inSameDayAs: current) {
            return "This Week"
        }
        if let next = WeekCalendar.calendar.date(byAdding: .day, value: 7, to: current),
           WeekCalendar.calendar.isDate(selectedWeekStart, inSameDayAs: next) {
            return "Next Week"
        }
        return "Week of \(selectedWeekStart.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var weekNavigator: some View {
        HStack {
            Button {
                moveWeek(by: -1)
            } label: {
                Label("Previous Week", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 32)
            }

            Spacer()
            VStack(spacing: 2) {
                Text(weekRangeText)
                    .font(.subheadline.weight(.semibold))
                if !WeekCalendar.calendar.isDate(selectedWeekStart, inSameDayAs: WeekCalendar.weekStart()) {
                    Button("Back to This Week") { selectedWeekStart = WeekCalendar.weekStart() }
                        .font(.caption)
                }
            }
            Spacer()

            Button {
                moveWeek(by: 1)
            } label: {
                Label("Next Week", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 32)
            }
        }
    }

    private var weekRangeText: String {
        let end = WeekCalendar.calendar.date(byAdding: .day, value: 6, to: selectedWeekStart)
            ?? selectedWeekStart
        return "\(selectedWeekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func moveWeek(by numberOfWeeks: Int) {
        selectedWeekStart = WeekCalendar.calendar.date(
            byAdding: .day,
            value: numberOfWeeks * 7,
            to: selectedWeekStart
        ) ?? selectedWeekStart
    }

    private func entriesForDay(_ date: Date) -> [MealPlanEntry] {
        entriesForSelectedWeek
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
