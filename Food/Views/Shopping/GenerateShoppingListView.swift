import CoreData
import SwiftUI

struct GenerateShoppingListView: View {
    struct Draft: Identifiable {
        let ingredient: AggregatedIngredient
        var isSelected: Bool
        var id: String { ingredient.id }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household

    @State private var startDate = WeekCalendar.weekStart()
    @State private var endDate = WeekCalendar.calendar.date(
        byAdding: .day,
        value: 6,
        to: WeekCalendar.weekStart()
    ) ?? .now
    @State private var drafts: [Draft] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Meals") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No Ingredients",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("There are no planned recipe ingredients in this date range.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ShoppingCategoryName.allCases) { category in
                        let indexes = draftIndexes(for: category)
                        if !indexes.isEmpty {
                            Section(category.rawValue.uppercased()) {
                                ForEach(indexes, id: \.self) { index in
                                    Button {
                                        drafts[index].isSelected.toggle()
                                    } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            Image(systemName: drafts[index].isSelected
                                                ? "checkmark.circle.fill"
                                                : "circle")
                                                .foregroundStyle(
                                                    drafts[index].isSelected
                                                        ? Color.green
                                                        : Color.secondary
                                                )
                                            Text(drafts[index].ingredient.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Text(quantityText(drafts[index].ingredient))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(minHeight: 40)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Generate Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedCount) \(selectedCount == 1 ? "Item" : "Items")") {
                        addSelectedItems()
                    }
                    .disabled(selectedCount == 0)
                }
            }
            .task { reload() }
            .onChange(of: startDate) { _, _ in reload() }
            .onChange(of: endDate) { _, _ in reload() }
            .alert("Couldn’t Generate List", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var selectedCount: Int { drafts.filter(\.isSelected).count }

    private func draftIndexes(for category: ShoppingCategoryName) -> [Int] {
        drafts.indices.filter { drafts[$0].ingredient.categoryName == category.rawValue }
    }

    private func quantityText(_ ingredient: AggregatedIngredient) -> String {
        var parts: [String] = []
        if let amount = ingredient.amount { parts.append(QuantityText.format(amount)) }
        if let unit = ingredient.unit, !unit.isEmpty { parts.append(unit) }
        return parts.joined(separator: " ")
    }

    private func reload() {
        let request = MealPlanEntry.fetchRequest()
        let dayAfterEnd = WeekCalendar.calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "household == %@", household),
            NSPredicate(
                format: "date >= %@ AND date < %@",
                WeekCalendar.calendar.startOfDay(for: startDate) as NSDate,
                WeekCalendar.calendar.startOfDay(for: dayAfterEnd) as NSDate
            )
        ])

        do {
            let entries = try context.fetch(request)
            drafts = ShoppingListAggregator
                .aggregate(ShoppingListAggregator.ingredients(from: entries))
                .map { Draft(ingredient: $0, isSelected: !$0.isPantryStaple) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSelectedItems() {
        let selected = drafts.filter(\.isSelected).map(\.ingredient)
        let request = ShoppingItem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "household == %@", household),
            NSPredicate(format: "isChecked == NO")
        ])

        do {
            let existingItems = try context.fetch(request)
            for ingredient in selected {
                if let existing = compatibleItem(for: ingredient, in: existingItems),
                   existing.hasQuantity, let amount = ingredient.amount {
                    existing.quantity += amount
                } else {
                    let item = ShoppingItem(context: context)
                    persistence.assign(item, to: household)
                    item.id = UUID()
                    item.name = ingredient.name
                    if let amount = ingredient.amount { item.quantity = amount }
                    item.unit = ingredient.unit
                    item.categoryName = ingredient.categoryName
                    item.isChecked = false
                    item.createdAt = .now
                    item.household = household
                }
            }
            try persistence.saveViewContext()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func compatibleItem(
        for ingredient: AggregatedIngredient,
        in items: [ShoppingItem]
    ) -> ShoppingItem? {
        guard ingredient.amount != nil else { return nil }
        return items.first {
            ($0.name ?? "").caseInsensitiveCompare(ingredient.name) == .orderedSame
                && normalized($0.unit) == normalized(ingredient.unit)
                && $0.hasQuantity
        }
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
