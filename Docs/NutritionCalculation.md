# Nutrition and leftovers: minimum reliable design

## Recommendation

Use deterministic arithmetic over verified ingredient data:

1. Prefer the exact UK product label for branded or formulation-sensitive foods (tofu, soy milk, protein powder, wraps, burgers, hummus, sauces).
2. Use the UK Composition of Foods Integrated Dataset (CoFID 2021) for generic foods.
3. Store the chosen source, version and preparation state with the ingredient.
4. Sum the whole recipe, then divide by the recipe's real yield.
5. Treat a leftover as a portion of the original batch, never as a second cooking event.

The Foundation Model may draft a recipe and suggest possible food matches. It must not invent nutrition, choose an ambiguous match without confirmation, perform the final arithmetic, or decide that an incomplete calculation is complete.

## Sources and offline data

[CoFID 2021](https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid) is the primary source. It is the official consolidated dataset for foods consumed in the UK and is only 4.42 MB as an XLSX file. A curated, conformed JSON or SQLite extract can therefore ship in the app and work offline. The [CoFID user guide](https://assets.publishing.service.gov.uk/media/60538e66d3bf7f03249bac58/McCance_and_Widdowsons_Composition_of_Foods_integrated_dataset_2021.pdf) says values are normally per 100 g (alcoholic drinks are per 100 ml), food codes identify entries, and names/descriptions include preparation details. It also defines `Tr` as trace and `N` as present without a reliable quantity; neither should be silently parsed as zero.

The user guide warns that foods vary and manufactured products change through reformulation. For an actual packaged ingredient, the current pack label is therefore a better match than a generic table entry. UK guidance permits nutrition values based on manufacturer analysis, known ingredient values, or generally accepted data, and explicitly identifies CoFID as accepted UK data ([technical guidance, pp. 18-19](https://assets.publishing.service.gov.uk/media/5a8010d8e5274a2e87db7a62/Nutrition_Technical_Guidance.pdf)).

CoFID use requires acknowledgement under the Open Government Licence; retain the dataset name/version and include attribution and an [OGL link](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/). Confirm the downloaded workbook contains no item-specific exception before distribution.

[USDA FoodData Central](https://fdc.nal.usda.gov/) is a useful fallback when CoFID has no suitable entry. Its data is CC0/public domain and it offers [downloadable CSV/JSON snapshots](https://fdc.nal.usda.gov/download-datasets/), but UK product labels and CoFID should remain primary. Do not make the app depend on the USDA API: it needs a protected API key and network access.

## Minimal schema

Do not introduce a full nutrient-tracking system. Add one reusable nutrition record and a small amount of linkage:

```text
FoodNutritionProfile
  id
  displayName
  brand?                         // product labels only
  sourceKind                     // cofid, productLabel, usda, manual
  sourceReference                // CoFID code, FDC id, barcode or label note
  sourceVersion
  preparationState               // raw, dry, cooked, drained, asSold, asPrepared
  basisQuantity                  // normally 100
  basisUnit                      // g, ml, or item
  energyKcal
  proteinG
  carbohydrateG?
  fatG?
  fibreG?
  verifiedAt?

RecipeIngredient (existing, extended)
  nutritionProfile?
  amount + unit                  // existing recipe/shopping quantity
  gramsPerUnit?                  // explicit food-specific conversion for item/slice/tbsp
  millilitresPerUnit?
  excludeFromNutrition           // water/optional garnish, explicitly chosen

MealPlanEntry (existing, clarified)
  servingsEaten                  // two people at dinner = 2
  servingsPrepared              // batch made at dinner = 4
  leftoverSource?               // relationship to the cooking entry
```

`FoodNutritionProfile` should be shared household data for product-label/manual entries. The bundled CoFID catalogue may be read-only; persist its stable code and a snapshot of the selected values so a later catalogue update cannot silently alter an existing recipe.

`gramsPerUnit` is ingredient-specific: one tomato, wrap or tablespoon cannot be assigned a universal weight. Prefer the pack's item weight for packaged foods. If no conversion exists, mark nutrition incomplete and ask for a weight; do not guess. Metric conversions such as kg to g and litre to ml are safe and deterministic.

## Calculation

For each included ingredient, first convert its recipe amount into the profile's basis unit. Then:

```text
ingredient kcal = amountInBasisUnit / basisQuantity * profile.energyKcal
ingredient protein = amountInBasisUnit / basisQuantity * profile.proteinG

batch kcal = sum(ingredient kcal)
batch protein = sum(ingredient protein)

kcal per serving = batch kcal / recipeYieldServings
protein per serving = batch protein / recipeYieldServings
```

Example: 275 g tofu whose label states 145 kcal per 100 g contributes `275 / 100 * 145 = 398.75 kcal` to the batch. If the complete recipe yields two equal servings, that tofu contributes about 199 kcal per serving.

Use the source's stated kcal whenever present. In particular, use CoFID's `KCALS` field rather than recomputing it: CoFID uses 3.75 kcal/g for available carbohydrate expressed as monosaccharides. UK label energy uses the factors in [Annex XIV](https://www.legislation.gov.uk/eur/2011/1169/pdfs/eur_20111169_2014-02-19_en.pdf): carbohydrate 4 kcal/g, protein 4, fat 9, fibre 2, polyols 2.4, alcohol 7, organic acids 3 and erythritol 0. A generic `protein*4 + carbs*4 + fat*9` fallback is not reliable when fibre, polyols or different carbohydrate definitions are involved.

Keep full precision internally. In the UI show an approximation such as `~620 kcal` and a sensible rounded protein value. Official England guidance recognises unavoidable variation in ingredients, preparation and portions and accepts a +/-20% difference for its out-of-home labelling regime; that law does not govern this household app, but it demonstrates why false precision is inappropriate ([calorie calculation guidance](https://www.gov.uk/government/publications/calorie-labelling-in-the-out-of-home-sector/calorie-labelling-in-the-out-of-home-sector-implementation-guidance#calculating-calorie-content)).

## Ingredient state rules

- Match the measured quantity to the reference state: dry rice with a dry-rice profile, cooked rice with a cooked-rice profile; drained beans with a drained-beans profile.
- Do not use a raw/dry profile with a cooked weight. Water gain or loss changes values per 100 g even when batch energy changes little.
- For canned food, calculate nutrition from edible drained weight. Convert shopping needs to tins using that product's drained weight separately.
- Include calorie-bearing oil, hummus, sauces and toppings. Use the amount actually consumed; oil or sauce discarded after cooking should not be counted as eaten.
- CoFID supplies an edible conversion factor for foods weighed with waste and a specific-gravity field for supported volume conversions. Treat these as food-specific metadata, not universal conversions.
- Per-serving nutrition does not require the finished cooked dish's weight when all consumed ingredients and the final serving yield are known. Finished weight is only needed for unequal portions or nutrition per 100 g of the finished dish.

## Leftovers

A four-serving bolognese cooked on Tuesday has one batch nutrition total and one per-serving result. Tuesday's two dinners and Wednesday's two leftover lunches each use the same per-serving nutrition.

Shopping generation must process the source entry once at `servingsPrepared = 4` and skip its linked leftover entry. The leftover entry records `servingsEaten = 2` and points to the Tuesday cooking entry. If a leftover has no source entry, flag it rather than silently skipping groceries.

This is more reliable than the current `isLeftover` boolean alone. The current aggregator correctly skips leftovers and scales the Tuesday batch to four servings, but it cannot prove which cooking event supplied a leftover. The existing `plannedServings` also means "prepared" for batch dinners and "eaten" for leftover lunches, so it should be split or given one explicit meaning.

## Current implementation gap and completion rules

Today `Recipe.caloriesPerServing` and `proteinPerServing` are stored estimates. `RecipeIngredient` has no food-composition reference, state, density or per-item weight, so those totals cannot yet be reproduced from the ingredient list. `ShoppingListAggregator` is appropriately conservative: it combines only identical units and skips leftovers.

A recipe may display calculated nutrition only when every material ingredient is either:

- linked to a verified profile and convertible to its basis unit, or
- explicitly excluded with a reason (for example water or an optional trace garnish).

Otherwise show `Nutrition incomplete`, list the unresolved ingredients, and omit the calorie figure. Generated recipes should not enter the usable rotation until this review passes.

## Required tests

- per-100 g and per-100 ml contribution maths
- kg/g and litre/ml conversion
- explicit item-to-gram conversion
- missing/ambiguous conversion produces incomplete nutrition
- raw/dry/cooked/drained profiles cannot be interchanged silently
- batch total divided by recipe yield
- serving scaling changes batch nutrition but not per-serving nutrition
- linked leftovers retain the original per-serving result and generate no second grocery purchase
- an orphan leftover is flagged
- full precision is retained before presentation rounding
