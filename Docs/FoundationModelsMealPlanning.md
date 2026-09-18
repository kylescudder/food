# Foundation Models for fresh weekly planning

Last verified against Apple sources: 17 September 2026.

## Recommendation

Apple's on-device Foundation Models framework is a good **optional recipe-idea assistant**, but it should not own Food's planning, nutrition, or shopping-list logic.

Build the core feature as a deterministic weekly rotation that works on every supported phone: choose from the household recipe library, avoid recently used recipes, preserve office-day and leftover rules, and let the user review or swap meals. When the on-device model is available, offer an explicit option to suggest one or more genuinely new vegan recipes. Save accepted recipes and the resulting dated meal entries into the existing shared Core Data household. Generate the shopping list from those saved recipe ingredients with the existing deterministic aggregator.

This gives the desired progression: the library grows while new ideas are useful, then the planner naturally cycles a sufficiently varied library. It also means one compatible phone can create a plan and the other phone can use the shared result without supporting Apple Intelligence.

Do not make AI-generated calorie, protein, allergen, food-safety, quantity arithmetic, or grocery aggregation results authoritative. In particular, the model must not invent the per-serving nutrition values that Food promises to label honestly.

## Why it fits

- `SystemLanguageModel` is an Apple-provided on-device text model. Apple says on-device model input and output remain private, inference works offline, adds no model to the app bundle, requires no API key or separate account, and has no per-request charge. Once the system model is installed, this meets Food's local-first and zero-infrastructure goals. [Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- The model is designed for generation, summarization, extraction, classification, and similar everyday tasks. Creating several recipe ideas from household preferences is a reasonable generation task. Apple explicitly says the device-scale model is not designed for world knowledge or advanced reasoning, which is why constraint enforcement and calculations must remain ordinary Swift code. [Explore the biggest updates from WWDC25](https://developer.apple.com/videos/play/meet-with-apple/201/)
- Guided Generation can produce a typed Swift result. `@Generable` and `@Guide` convert a type to a schema, and constrained sampling can restrict values, array counts, numeric ranges, and enumerated choices. A generated proposal can therefore contain typed days, meal slots, existing recipe IDs, and new recipe drafts instead of fragile free-form JSON. [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), [`Generable`](https://developer.apple.com/documentation/foundationmodels/generable)
- Tool calling can let the model query an app database or other source of truth at runtime. It could expose a read-only tool for recent meals or compact recipe candidates, although passing a prefiltered candidate list directly is simpler for V1. A tool's output returns to the model; tools and their results also consume context. [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [`Tool`](https://developer.apple.com/documentation/foundationmodels/tool)

## Proposed product flow

1. **Create Next Week** first runs normal Swift selection against saved recipes and recent `MealPlanEntry` history.
2. Offer a small choice such as **Use My Recipes** or **Include 1 New Idea**. Do not expose technical language such as “Foundation Models” or “Apple Intelligence” in the normal workflow.
3. For AI generation, give the model only compact trusted context: vegan requirement, meal type, serving defaults, office days, leftover pairings, disliked/recent recipe IDs, existing recipe names/tags, and allowed units/categories. Do not send the entire recipe library; the on-device model has a 4,096-token session context that includes prompts, instructions, schemas, tools, tool results, and responses. [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
4. Ask for a typed `WeeklyPlanDraft` whose existing meals reference stable recipe IDs and whose new ideas contain ingredient and step drafts. Limit novelty explicitly, for example one new dinner rather than generating 21 new recipes.
5. Validate in Swift before displaying: all meals are present, recipe IDs exist, every ingredient has an allowed unit/category, servings are positive, meals are vegan, leftover entries point at the intended earlier recipe, and no recently excluded recipe slipped through.
6. Show a review screen where either person can replace, edit, reject, or retry a suggestion. Clearly identify the new recipe as generated. Apple advises keeping people in control, identifying AI use, and retaining a useful non-AI path. [Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)
7. Persist only the accepted plan and recipes. Calculate shopping items from persisted ingredients using Food's tested same-unit aggregation; never ask the model to total the grocery list.

The rotation engine is not throwaway work. It is the permanent planner and fallback; AI only expands the recipe pool when requested.

## Availability and fallback requirements

The Foundation Models APIs and `SystemLanguageModel` were introduced in iOS 26. Food can retain its iOS 18 deployment target, but the code must compile with Xcode 26 or later and be isolated behind `if #available(iOS 26, *)`. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [Develop in Swift requirements](https://developer.apple.com/tutorials/develop-in-swift/welcome-to-machine-learning-and-ai)

As of this review, Apple's current Apple Intelligence requirements for iPhone are iPhone 15 Pro/Pro Max, iPhone 16 models or later, and iPhone Air. iOS 27 requires the device and Siri languages to match and lists support for English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, simplified and traditional Chinese, Japanese, and Korean. Availability also varies by region; Apple Intelligence remains unavailable under the documented China-mainland conditions. [How to get Apple Intelligence](https://support.apple.com/en-us/121115)

Never infer readiness only from OS version. Check `SystemLanguageModel.default.availability` and the current locale. Apple documents these unavailable states:

- `.deviceNotEligible`
- `.appleIntelligenceNotEnabled`
- `.modelNotReady` — model assets download automatically according to network, battery, and system load

Also handle unsupported locale, guardrail/refusal, context-size, cancellation, and general generation errors. The ordinary rotation and manual recipe flow must remain available in every case. [`SystemLanguageModel.Availability`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum), [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)

Offline generation works only after the system model is ready on that device. An offline phone cannot fetch missing model assets, so “model not ready” must fall back rather than block next-week planning.

Apple updates the on-device model with OS releases; the current documentation identifies distinct behavior for iOS 26.0–26.3, 26.4, and 27.0. Prompt and validation tests need coverage on each supported model generation because identical prompts can change behavior after an OS update. [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)

## Reliability and policy limits

- Generated output is nondeterministic even with a schema. Guided Generation guarantees the shape and constrained values, not that a recipe tastes good, satisfies every natural-language rule, has correct nutrition, or is safe. Treat it as a draft.
- The 4K on-device context is small for a whole recipe library plus a 21-meal plan. Prefilter in Swift, keep the generated schema compact, use fresh sessions, and split “select a plan” from “draft one new recipe” if necessary. [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- Apple requires app-specific safety work in addition to built-in guardrails. Keep untrusted user text in prompts rather than privileged instructions, handle `guardrailViolation` and refusals, and test prompts when the system model changes. [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
- Apple's acceptable-use rules prohibit harmful or illegal uses and inaccurate or dangerous unsupervised decisions in high-risk medical, legal, employment, or finance contexts. Meal inspiration is allowed, but presenting generated nutrition as medical advice or making unsupervised health decisions would be inappropriate. [Acceptable use requirements](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework)

## Entitlements and infrastructure

Ordinary use of the on-device `SystemLanguageModel` is a standard SDK integration: Apple documents no API key, account, hosted service, or app-specific managed entitlement. Food still needs its existing signing and CloudKit entitlements for household sharing, but on-device recipe generation adds no server to operate.

No custom adapter is needed; shipping an adapter requires Apple's separate Foundation Models Framework Adapter entitlement and version-specific adapter assets. [Foundation Models adapter training](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)

Do not use `PrivateCloudComputeLanguageModel` for this feature. It is an iOS 27 server-side option with stronger reasoning and a 32K context, but it requires a network connection, has daily quotas, and needs a managed entitlement. That weakens Food's offline guarantee without being necessary for constrained meal ideas. [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [`com.apple.developer.private-cloud-compute`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute)

The App Store-facing obligations are to comply with the current Foundation Models acceptable-use requirements and Apple Developer Program agreement, keep reasonable guardrails, disclose the AI feature honestly, and give the user control over accepting generated content. There is no separate external AI privacy policy burden caused by sending prompts to a third party because this recommendation uses only the on-device system model; the app's own handling and CloudKit sharing of accepted recipes still needs to be represented accurately in its privacy disclosures. [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/), [Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)
