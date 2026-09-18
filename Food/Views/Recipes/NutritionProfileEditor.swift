import CoreData
import SwiftUI

struct NutritionProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var ingredient: RecipeIngredient

    @State private var brand: String
    @State private var recipeAmount: Double
    @State private var recipeUnit: String
    @State private var basisUnit: String
    @State private var caloriesPer100: Double
    @State private var proteinPer100: Double
    @State private var basisAmountPerItem: Double
    @State private var errorMessage: String?

    init(ingredient: RecipeIngredient) {
        self.ingredient = ingredient
        let profile = ingredient.nutritionProfile
        _brand = State(initialValue: profile?.brand ?? "")
        _recipeAmount = State(initialValue: ingredient.hasNutritionAmount
            ? ingredient.nutritionAmount
            : (ingredient.hasAmount ? ingredient.amount : 0))
        _recipeUnit = State(initialValue: ingredient.nutritionUnit ?? ingredient.unit ?? "g")
        _basisUnit = State(initialValue: profile?.basisUnit ?? "g")
        _caloriesPer100 = State(initialValue: profile?.energyKcal ?? 0)
        _proteinPer100 = State(initialValue: profile?.proteinG ?? 0)
        _basisAmountPerItem = State(initialValue: ingredient.hasGramsPerUnit
            ? ingredient.gramsPerUnit
            : (ingredient.hasMillilitresPerUnit ? ingredient.millilitresPerUnit : 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Brand or product", text: $brand)
                    LabeledContent("Ingredient", value: ingredient.name ?? "Ingredient")
                } header: {
                    Text("Pack")
                } footer: {
                    Text("Enter the values printed on the product you actually use. You can do this before shopping from a retailer listing or after checking the pack.")
                }

                Section("Amount in this recipe") {
                    TextField("Amount", value: $recipeAmount, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: $recipeUnit)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Picker("Label basis", selection: $basisUnit) {
                        Text("per 100 g").tag("g")
                        Text("per 100 ml").tag("ml")
                    }
                    .pickerStyle(.segmented)
                    TextField("Calories", value: $caloriesPer100, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $proteinPer100, format: .number)
                        .keyboardType(.decimalPad)
                    if usesItemUnit {
                        TextField(
                            basisUnit == "g" ? "Grams in one item" : "Millilitres in one item",
                            value: $basisAmountPerItem,
                            format: .number
                        )
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Nutrition from the label")
                } footer: {
                    Text("Food calculates the whole recipe from these values, then divides by the recipe’s serving count.")
                }
            }
            .navigationTitle("Product Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Couldn’t Save Nutrition", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var normalizedRecipeUnit: String {
        recipeUnit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var usesItemUnit: Bool {
        !["g", "kg", "ml", "l"].contains(normalizedRecipeUnit)
    }

    private var isValid: Bool {
        recipeAmount > 0
            && caloriesPer100 >= 0
            && proteinPer100 >= 0
            && (!usesItemUnit || basisAmountPerItem > 0)
    }

    private func save() {
        guard isValid,
              let household = ingredient.recipe?.household,
              let context = ingredient.managedObjectContext else { return }

        let profile = FoodNutritionProfile(context: context)
        persistence.assign(profile, to: household)
        profile.id = UUID()
        profile.displayName = ingredient.name
        profile.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.sourceKind = "Product label"
        profile.sourceReference = profile.brand?.isEmpty == false
            ? profile.brand
            : "Pack label"
        profile.sourceVersion = ISO8601DateFormatter().string(from: .now)
        profile.preparationState = "as sold"
        profile.basisQuantity = 100
        profile.basisUnit = basisUnit
        profile.energyKcal = caloriesPer100
        profile.proteinG = proteinPer100
        profile.household = household

        ingredient.amount = recipeAmount
        ingredient.unit = recipeUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        ingredient.nutritionAmount = recipeAmount
        ingredient.nutritionUnit = ingredient.unit
        ingredient.excludeFromNutrition = false
        if usesItemUnit, basisUnit == "g" {
            ingredient.gramsPerUnit = basisAmountPerItem
        } else if usesItemUnit {
            ingredient.millilitresPerUnit = basisAmountPerItem
        }
        ingredient.nutritionProfile = profile

        do {
            try persistence.saveViewContext()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
