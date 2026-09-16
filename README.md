# Food

![Food app icon](Branding/AppIcon.png)

## What it is

Food is a small, shared household meal planner for Kyle and Rhiannon. It keeps the current week, practical vegan recipes, cooking checklists, and one shared grocery list in a native iPhone app.

The app is local-first. Normal reads and writes use Core Data’s on-device SQLite stores, so an already-downloaded household remains useful offline. Apple’s CloudKit mirroring exports and imports changes when connectivity returns. There is no external server, account system, analytics SDK, or third-party dependency.

The app icon master is available at [`Food/Resources/Brand/AppIconMaster.png`](Food/Resources/Brand/AppIconMaster.png), with a reusable project copy at [`Branding/AppIcon.png`](Branding/AppIcon.png).

## Architecture

The shared data layer uses **Core Data + `NSPersistentCloudKitContainer`**, not SwiftData:

- One local SQLite store mirrors the owner’s CloudKit private database.
- A second local SQLite store mirrors records shared with the signed-in iCloud user.
- `Household` is the root of a connected object graph containing recipes, recipe ingredients and steps, dated meal entries, shopping categories, and shopping items.
- Core Data persistent history and remote-change notifications merge CloudKit imports into the SwiftUI view context.
- New objects are assigned to the same persistent store as their household, which keeps participant edits in the shared record zone.
- Tests and previews can use the same managed-object model with an in-memory, non-CloudKit store.

SwiftData’s managed CloudKit integration currently covers a person’s private database but does not expose `CKShare` or shared-database configuration. Apple’s supported high-level path for editable shares plus an offline local replica is `NSPersistentCloudKitContainer`. The researched decision, limitations, and primary Apple sources are in [`Docs/PersistenceDecision.md`](Docs/PersistenceDecision.md).

CloudKit synchronization is eventual rather than a guaranteed subsecond real-time channel. On supported network conditions, remote notifications normally bring the other phone up to date quickly; Apple advises that ordinary synchronization may take around a minute. Share acceptance itself requires a network connection.

## Requirements

- macOS with Xcode 16 or newer (use the current stable Xcode)
- iOS 18 or newer deployment target
- An Apple Developer team for CloudKit/device builds
- Two physical devices with different iCloud accounts to verify household sharing end to end

The repository contains no package-manager dependencies.

## Running locally

1. Open `Food.xcodeproj` in Xcode.
2. Select the `Food` scheme and an iPhone simulator running iOS 18 or newer.
3. For a simulator run that does not require signing or iCloud, choose **Product → Scheme → Edit Scheme → Run → Arguments** and add `-LocalStore`.
4. Build and run. Choose **Create Household**; `The Scudders` is prefilled.
5. The 14 recipes, 21 current-week meal slots, and ten shopping categories are seeded once. Removing and reinstalling the local app resets this development data.

`-LocalStore` uses a durable on-device SQLite store but intentionally disables the share button. Remove the argument to exercise CloudKit.

To run the tests in Xcode, press **⌘U**. From Terminal on a Mac, choose an installed simulator name and run:

```sh
xcodebuild \
  -project Food.xcodeproj \
  -scheme Food \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

## CloudKit Setup

The checked-in placeholder identifiers are:

- Bundle ID: `com.kyle.food`
- CloudKit container: `iCloud.com.kyle.food`

These identifiers must be available to your Apple Developer team. If they are not, replace the CloudKit identifier in both `Food/Food.entitlements` and `PersistenceController.cloudKitContainerIdentifier`, then use the matching container below.

1. Select the `Food` target, open **Signing & Capabilities**, select your development team, and set a unique bundle identifier.
2. Add the **iCloud** capability, enable **CloudKit**, and create or select the exact CloudKit container used by the code and entitlements.
3. Add **Push Notifications**. The checked-in entitlements contain the development `aps-environment`; Xcode and the provisioning profile control its signed value.
4. Add **Background Modes** and enable **Remote notifications** so imports can wake the app promptly.
5. Confirm `Food/App/Info.plist` contains `CKSharingSupported = YES` and the `remote-notification` background mode. Both are checked in.
6. Sign in to an iCloud account on the device (and in the simulator if using CloudKit there), then run without `-LocalStore`.
7. In a development build only, temporarily add the launch argument `-InitializeCloudKitSchema`, launch once while online, verify the success alert, then remove the argument. This calls Apple’s `initializeCloudKitSchema()` for the development environment.
8. Open CloudKit Console, select the container’s **Development** environment, and inspect the generated record types and fields.
9. Before TestFlight or release, use CloudKit Console to deploy the schema to **Production**. CloudKit production field/type removals and renames are not supported, so treat model evolution carefully.

The app’s Core Data model intentionally has no unique constraints, uses optional CloudKit-compatible relationships with inverses, and avoids the Deny delete rule.

## Testing Sharing

CloudKit sharing cannot be proven with one unsigned simulator. Use two physical devices and two different iCloud accounts:

1. Install the same signed build on both phones and confirm both are online.
2. On Kyle’s phone, create `The Scudders` and wait for the initial CloudKit export to finish.
3. In the Week tab, tap the people button, then **Share or Manage People**.
4. Invite Rhiannon through Apple’s native sharing sheet with read/write permission.
5. On Rhiannon’s phone, open the invitation from Messages or Mail and accept it. The app’s scene delegate passes the share metadata into the shared persistent store.
6. Leave the app open briefly while the initial graph imports. The Week, Recipes, and Shopping tabs should then show the same household.
7. With both devices online, add and check different shopping items on each phone and verify the changes arrive on the other.
8. Put each phone in Airplane Mode in turn, read recipes, change meals, and add/check items. Reconnect and verify the changes converge.
9. Test simultaneous edits to the same item. V1 relies on Core Data/CloudKit’s property-level merge behavior and does not add a custom conflict engine.

If acceptance does not arrive, verify that both accounts have iCloud Drive enabled, the invitation targets the second account, both builds use the same bundle/container/environment, `CKSharingSupported` is present, and the shared-store import has had time to complete.

## Current Scope

- Current week grouped by actual Monday–Sunday dates
- Tuesday and Wednesday office-day labels
- Meal-to-recipe navigation and meal swapping
- Fourteen seeded vegan recipes with per-serving nutrition labels
- Ephemeral, resettable ingredient and method checklists
- Serving-based ingredient scaling
- Shared shopping list with manual add, edit, delete, check, uncheck, and Clear Checked
- Current-week or custom-date-range grocery generation
- Basic same-name/same-unit aggregation, with incompatible units kept separate
- Pantry-staple deselection before generated items are added
- CloudKit household creation, native invitation UI, share acceptance, and offline local stores

Recipe editing is deliberately deferred: V1 prioritizes reliable viewing, cooking, meal swapping, and shopping.

## Explicitly Out of Scope

- Custom accounts or profiles
- Web app
- Android app
- Calorie tracking or personal calorie targets
- Weight tracking
- HealthKit
- Push-notification features (CloudKit’s silent remote notifications are infrastructure, not a user-facing notification feature)
- AI meal generation
- External backend or custom synchronization service
- Analytics or advertising
- Pantry inventory management
- Complex unit conversion
