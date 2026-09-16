import CoreData
import SwiftUI

struct ShoppingView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @FetchRequest private var items: FetchedResults<ShoppingItem>

    @State private var showingAddItem = false
    @State private var showingGenerator = false
    @State private var showingClearConfirmation = false
    @State private var editingItem: ShoppingItem?
    @State private var errorMessage: String?

    init(household: Household) {
        self.household = household
        _items = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \ShoppingItem.categoryName, ascending: true),
                NSSortDescriptor(keyPath: \ShoppingItem.createdAt, ascending: true)
            ],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Shopping Items",
                        systemImage: "cart",
                        description: Text("Add an item or generate groceries from this week’s meals.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(ShoppingCategoryName.allCases) { category in
                        let categoryItems = itemsForCategory(category)
                        if !categoryItems.isEmpty {
                            Section(category.rawValue.uppercased()) {
                                ForEach(categoryItems, id: \.objectID) { item in
                                    ShoppingItemRow(item: item) {
                                        item.isChecked.toggle()
                                        saveOrReportError()
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            context.delete(item)
                                            saveOrReportError()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingItem = item
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }
                    }

                    if hasCheckedItems {
                        Section {
                            Button("Clear Checked", role: .destructive) {
                                showingClearConfirmation = true
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingGenerator = true
                    } label: {
                        Label("Generate Shopping List", systemImage: "wand.and.stars")
                    }
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) {
                ShoppingItemEditor(household: household)
            }
            .sheet(item: $editingItem) { item in
                ShoppingItemEditor(household: household, item: item)
            }
            .sheet(isPresented: $showingGenerator) {
                GenerateShoppingListView(household: household)
            }
            .confirmationDialog(
                "Remove all checked items?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Checked", role: .destructive) { clearChecked() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn’t Update Shopping", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var hasCheckedItems: Bool { items.contains(where: \.isChecked) }

    private func itemsForCategory(_ category: ShoppingCategoryName) -> [ShoppingItem] {
        items
            .filter { ($0.categoryName ?? ShoppingCategoryName.cupboard.rawValue) == category.rawValue }
            .sorted {
                if $0.isChecked != $1.isChecked { return !$0.isChecked }
                return ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
    }

    private func clearChecked() {
        items.filter(\.isChecked).forEach(context.delete)
        saveOrReportError()
    }

    private func saveOrReportError() {
        do {
            try persistence.saveViewContext()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShoppingItemRow: View {
    @ObservedObject var item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 13) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Item")
                        .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                        .strikethrough(item.isChecked, color: .secondary)
                    if item.hasQuantity || !(item.unit ?? "").isEmpty {
                        Text(QuantityText.ingredient(
                            amount: item.hasQuantity ? item.quantity : nil,
                            unit: item.unit,
                            name: ""
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name ?? "Shopping item")
        .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
    }
}
