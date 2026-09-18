import SwiftUI

struct ShoppingItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var persistence: PersistenceController

    @ObservedObject var household: Household
    let item: ShoppingItem?

    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var category: ShoppingCategoryName
    @State private var errorMessage: String?
    @FocusState private var nameIsFocused: Bool

    init(household: Household, item: ShoppingItem? = nil) {
        self.household = household
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _quantity = State(initialValue: item?.hasQuantity == true
            ? QuantityText.format(item?.quantity ?? 0)
            : "")
        _unit = State(initialValue: item?.unit ?? "")
        _category = State(initialValue: ShoppingCategoryName(
            rawValue: item?.categoryName ?? ""
        ) ?? .fruitAndVeg)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $name)
                        .focused($nameIsFocused)
                        .submitLabel(.done)
                }

                Section("Optional quantity") {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("Unit (g, ml, tins…)", text: $unit)
                        .textInputAutocapitalization(.never)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ShoppingCategoryName.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle(item == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { if item == nil { nameIsFocused = true } }
            .alert("Couldn’t Save Item", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private func save() {
        let target = item ?? ShoppingItem(context: context)
        if item == nil {
            persistence.assign(target, to: household)
            target.id = UUID()
            target.createdAt = .now
            target.isChecked = false
            target.household = household
        }

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.categoryName = category.rawValue
        target.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : unit.trimmingCharacters(in: .whitespacesAndNewlines)

        if let parsed = QuantityText.parse(quantity), parsed > 0 {
            target.quantity = parsed
        } else {
            target.setPrimitiveValue(nil, forKey: "quantity")
        }

        do {
            try persistence.saveViewContext()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
