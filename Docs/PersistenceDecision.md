# Persistence decision: Core Data with CloudKit sharing

Last verified against Apple sources: 15 September 2026.

## Decision

Use **Core Data + `NSPersistentCloudKitContainer`**, with two local SQLite stores mirrored to one CloudKit container:

- a private-database store (`databaseScope = .private`)
- a shared-database store (`databaseScope = .shared`)

This is Apple's managed, local-first route that supports both an object graph and collaboration between different iCloud users. Apple's CloudKit technology guide says `NSPersistentCloudKitContainer` maintains a local replica, supports private and shared databases, and is preferred when an app does not need granular control over synchronization. [Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)

Do not use SwiftData for the shared household store, and do not build a parallel `CKRecord`/`CKSyncEngine` synchronization layer.

## Why not SwiftData

SwiftData's documented automatic CloudKit feature is explicitly framed as syncing data "across a person's devices." Its `ModelConfiguration.CloudKitDatabase` discovery options expose automatic, private, and none, but no shared-database option. SwiftData delegates that managed synchronization to `NSPersistentCloudKitContainer`; this does not expose the latter's sharing APIs through SwiftData. [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [`ModelConfiguration.CloudKitDatabase`](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct)

Apple DTS stated directly that SwiftData + CloudKit public or shared databases were unsupported and recommended staying with `NSPersistentCloudKitContainer` when that integration is required. A May 2026 Apple DTS response still describes SwiftData as using its own `NSPersistentCloudKitContainer` internally and warns that bolting a second Core Data sharing stack beside it can cause two mirroring containers to conflict. [Apple DTS: SwiftData with shared and private containers](https://developer.apple.com/forums/thread/756721?answerId=790189022#790189022), [Apple DTS: CKShare-style sharing support in SwiftData](https://developer.apple.com/forums/thread/825496?answerId=887006022#887006022)

Direct CloudKit or `CKSyncEngine` can support shared databases, but would move record mapping, local persistence, synchronization state, and conflicts into application code. That contradicts the requirement to avoid a custom synchronization engine, while adding no useful benefit for this small household graph. [Deciding whether CloudKit is right for your app](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)

## Implementation shape

1. Configure one `NSPersistentCloudKitContainer` with separate private and shared store descriptions. Enable persistent history tracking and remote-change notifications on both. A single managed object context can access both stores. This is the exact pattern in Apple's sharing guidance and WWDC session. [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users), [Build apps that share data through CloudKit and Core Data](https://developer.apple.com/videos/play/wwdc2021/10015/)
2. Make `Household` the root of one connected object graph containing its recipes, ingredients, plan entries, categories, and shopping items. Create Kyle's household in the private store, then create one zone share with `share([household], to: nil)` and present Apple's native sharing UI. `NSPersistentCloudKitContainer` traverses related objects into the share; it does not support relationships between different shares. New shared objects must remain connected to the household and in its store/share zone. When Core Data cannot infer the zone from relationships, associate them with the existing `CKShare` using `share(_:to:)`. [`share(_:to:completion:)`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/sharemanagedobjects:toshare:completion:), [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)
3. Set the share's participant permission to read/write. On acceptance, a SwiftUI scene delegate receives the share metadata and calls `acceptShareInvitations(from:into:)` with the shared store. Set `CKSharingSupported = YES` in `Info.plist`. [Accepting Share Invitations in a SwiftUI App](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app)
4. Fetch household data from both stores: an owner's graph resides under their private database, while a participant's accepted graph appears in their shared store. Route inserts to the same persistent store as their household and check Core Data's share permission APIs before offering destructive edits where appropriate. [`canUpdateRecord(forManagedObjectWith:)`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/canupdaterecord(formanagedobjectwith:))
5. Keep the persistence boundary small: production creates the two CloudKit-backed stores; tests and previews create an in-memory `NSPersistentContainer` from the same managed object model with CloudKit disabled.

The CloudKit-compatible model must avoid unique constraints, make relationships optional with inverses, and avoid the Deny delete rule. Production CloudKit record types and fields cannot be renamed or removed after schema deployment, so initialize and inspect the development schema before promoting it. [Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit)

## Offline and synchronization behavior

The local store is the application's source during normal fetches and saves: Core Data does not query CloudKit during a fetch, and a save writes locally and records persistent history before `NSPersistentCloudKitContainer` later exports it. This satisfies offline reading and editing after the shared household has been downloaded. [TN3163: Understanding the synchronization of `NSPersistentCloudKitContainer`](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)

Two limits should be presented honestly:

- Accepting a share requires connectivity; Apple's acceptance API explicitly requires an active network connection. Once accepted and imported, ordinary use is local-first. [`acceptShareInvitations(from:into:completion:)`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/acceptshareinvitations(from:into:completion:))
- CloudKit synchronization is eventual, not a guaranteed instant real-time channel. Apple says changes move on the system's natural cadence and are generally synchronized within about a minute. The UI should merge imported persistent-history transactions on remote-change notifications, but it must not promise subsecond grocery updates. [Syncing a Core Data Store with CloudKit](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit)

No application-level synchronization or conflict-resolution engine is needed for V1; rely on Core Data/CloudKit mirroring and test simultaneous edits on two physical devices before release.
