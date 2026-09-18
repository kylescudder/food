import CoreData
import SwiftUI

struct RecipesView: View {
    @ObservedObject var household: Household
    @FetchRequest private var recipes: FetchedResults<Recipe>
    @State private var searchText = ""

    init(household: Household) {
        self.household = household
        _recipes = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.name, ascending: true)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    var body: some View {
        NavigationStack {
            List(filteredRecipes, id: \.objectID) { recipe in
                let calculation = NutritionCalculator.calculate(recipe: recipe)
                let calories = calculation.isComplete
                    ? calculation.perServing.calories
                    : (recipe.hasCalories ? recipe.caloriesPerServing : nil)
                let protein = calculation.isComplete
                    ? calculation.perServing.proteinGrams
                    : (recipe.hasProtein ? recipe.proteinPerServing : nil)
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.name ?? "Recipe")
                            .font(.body.weight(.medium))
                        HStack(spacing: 10) {
                            Text("Serves \(QuantityText.format(recipe.defaultServings))")
                            if let calories {
                                Text("~\(QuantityText.format(calories)) kcal")
                            }
                            if let protein {
                                Text("~\(QuantityText.format(protein)) g protein")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            .navigationTitle("Recipes")
            .searchable(text: $searchText, prompt: "Find a recipe")
        }
    }

    private var filteredRecipes: [Recipe] {
        guard !searchText.isEmpty else { return Array(recipes) }
        return recipes.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
                || ($0.tags ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
}
