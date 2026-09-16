import CoreData
import SwiftUI

struct RecipeDetailView: View {
    @ObservedObject var recipe: Recipe
    @State private var servings: Int
    @State private var checkedIngredients: Set<NSManagedObjectID> = []
    @State private var checkedSteps: Set<NSManagedObjectID> = []

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: max(1, Int(recipe.defaultServings.rounded())))
    }

    var body: some View {
        List {
            if let description = recipe.recipeDescription, !description.isEmpty {
                Text(description)
                    .foregroundStyle(.secondary)
            }

            Section {
                servingControl
                nutritionSummary
            }

            Section("Ingredients") {
                ForEach(recipe.sortedIngredients, id: \.objectID) { ingredient in
                    ChecklistRow(
                        isChecked: checkedIngredients.contains(ingredient.objectID),
                        text: ingredientText(ingredient)
                    ) {
                        toggle(ingredient.objectID, in: &checkedIngredients)
                    }
                }
            }

            Section(recipe.cookingRequired ? "Method" : "Preparation") {
                ForEach(recipe.sortedSteps, id: \.objectID) { step in
                    ChecklistRow(
                        isChecked: checkedSteps.contains(step.objectID),
                        text: step.instruction ?? "Step"
                    ) {
                        toggle(step.objectID, in: &checkedSteps)
                    }
                }
            }

            if let note = recipe.nutritionNote, !note.isEmpty {
                Section {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(recipe.name ?? "Recipe")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !checkedIngredients.isEmpty || !checkedSteps.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        checkedIngredients.removeAll()
                        checkedSteps.removeAll()
                    }
                }
            }
        }
    }

    private var servingControl: some View {
        HStack {
            Text("Serves")
            Spacer()
            Button {
                servings = max(1, servings - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(servings == 1)
            .accessibilityLabel("Decrease servings")

            Text("\(servings)")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 28)

            Button {
                servings = min(12, servings + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(servings == 12)
            .accessibilityLabel("Increase servings")
        }
    }

    private var nutritionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per serving")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 22) {
                Label(
                    recipe.hasCalories ? "~\(QuantityText.format(recipe.caloriesPerServing)) kcal" : "Not estimated",
                    systemImage: "flame"
                )
                Label(
                    recipe.hasProtein ? "~\(QuantityText.format(recipe.proteinPerServing)) g protein" : "Not estimated",
                    systemImage: "leaf"
                )
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func ingredientText(_ ingredient: RecipeIngredient) -> String {
        let amount = ingredient.hasAmount
            ? RecipeServingScaler.scaledAmount(
                ingredient.amount,
                from: recipe.defaultServings,
                to: Double(servings)
            )
            : nil
        return QuantityText.ingredient(
            amount: amount,
            unit: ingredient.unit,
            name: ingredient.name ?? "Ingredient",
            note: ingredient.note
        )
    }

    private func toggle(_ id: NSManagedObjectID, in set: inout Set<NSManagedObjectID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

private struct ChecklistRow: View {
    let isChecked: Bool
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChecked ? Color.green : Color.secondary)
                    .padding(.top, 1)
                Text(text)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .strikethrough(isChecked, color: .secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
    }
}
