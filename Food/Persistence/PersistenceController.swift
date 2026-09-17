import CloudKit
import Combine
import CoreData
import Foundation

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()
    static let cloudKitContainerIdentifier = "iCloud.com.kyle.food"

    enum PersistenceError: LocalizedError {
        case notReady

        var errorDescription: String? {
            switch self {
            case .notReady: "The meal planner database is still loading."
            }
        }
    }

    let container: NSPersistentCloudKitContainer
    let cloudKitEnabled: Bool

    @Published private(set) var isReady = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var shareStatusMessage: String?

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    private let stateLock = NSLock()
    private var pendingShareMetadata: [CKShare.Metadata] = []
    private var historyTokens: [String: NSPersistentHistoryToken] = [:]
    private var remoteChangeObserver: NSObjectProtocol?

    init(inMemory: Bool = false, cloudKitEnabled: Bool? = nil) {
        let launchRequestsLocalStore = ProcessInfo.processInfo.arguments.contains("-LocalStore")
        self.cloudKitEnabled = cloudKitEnabled ?? (!inMemory && !launchRequestsLocalStore)
        container = NSPersistentCloudKitContainer(name: "Food")

        let descriptions = Self.makeStoreDescriptions(
            inMemory: inMemory,
            cloudKitEnabled: self.cloudKitEnabled
        )
        container.persistentStoreDescriptions = descriptions
        configureViewContext()
        loadStores(descriptions: descriptions)
    }

    deinit {
        if let remoteChangeObserver { NotificationCenter.default.removeObserver(remoteChangeObserver) }
    }

    func createHousehold(named rawName: String) throws -> Household {
        guard isReady, let store = privateStore else { throw PersistenceError.notReady }

        let context = container.viewContext
        let household = Household(context: context)
        context.assign(household, to: store)
        household.id = UUID()
        household.name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "The Scudders"
            : rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        household.createdAt = .now
        household.seedVersion = 0

        do {
            try context.save()
            try SeedData.seedIfNeeded(household: household, in: context)
            return household
        } catch {
            context.rollback()
            throw error
        }
    }

    func ensureSeedData(for household: Household) {
        guard household.seedVersion < SeedData.currentVersion else { return }
        do {
            try SeedData.seedIfNeeded(household: household, in: container.viewContext)
        } catch {
            container.viewContext.rollback()
            publishShareStatus("Couldn’t finish creating the starter plan: \(error.localizedDescription)")
        }
    }

    func saveViewContext() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        try context.save()
    }

    func assign(_ object: NSManagedObject, to household: Household) {
        if let store = household.objectID.persistentStore {
            container.viewContext.assign(object, to: store)
        }
    }

    func canUpdate(_ object: NSManagedObject) -> Bool {
        guard cloudKitEnabled else { return true }
        do {
            return try container.canUpdateRecord(forManagedObjectWith: object.objectID)
        } catch {
            // A newly inserted local object has no mirrored record yet and remains editable.
            return object.objectID.isTemporaryID
        }
    }

    func existingShare(for household: Household) -> CKShare? {
        guard cloudKitEnabled else { return nil }
        return try? container.fetchShares(matching: [household.objectID])[household.objectID]
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard cloudKitEnabled else {
            publishShareStatus("Sharing isn’t available in this build.")
            return
        }

        stateLock.lock()
        guard let sharedStore else {
            pendingShareMetadata.append(metadata)
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            if let error {
#if DEBUG
                print("Share acceptance failed: \(error)")
#endif
                self?.publishShareStatus("Couldn’t join the household. Check your connection and try again.")
            } else {
                self?.publishShareStatus("Household joined.")
            }
        }
    }

    func clearShareStatus() {
        shareStatusMessage = nil
    }

    private func configureViewContext() {
        container.viewContext.name = "viewContext"
        container.viewContext.transactionAuthor = "FoodApp"
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private func loadStores(descriptions: [NSPersistentStoreDescription]) {
        var remaining = descriptions.count
        var errors: [Error] = []

        container.loadPersistentStores { [weak self] description, error in
            guard let self else { return }
            self.stateLock.lock()
            defer { self.stateLock.unlock() }

            if let error { errors.append(error) }
            remaining -= 1
            guard remaining == 0 else { return }

            if errors.isEmpty {
                self.resolveLoadedStores()
                self.startObservingRemoteChanges()
#if DEBUG
                if self.cloudKitEnabled,
                   ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
                    do {
                        try self.container.initializeCloudKitSchema()
                        self.publishShareStatus("CloudKit development schema initialized.")
                    } catch {
                        self.publishShareStatus("CloudKit schema initialization failed: \(error.localizedDescription)")
                    }
                }
#endif
                let pending = self.pendingShareMetadata
                self.pendingShareMetadata.removeAll()
                DispatchQueue.main.async {
                    self.isReady = true
                    pending.forEach(self.acceptShare)
                }
            } else {
                let message = errors.map(\.localizedDescription).joined(separator: "\n")
                DispatchQueue.main.async { self.loadErrorMessage = message }
            }
        }
    }

    private func resolveLoadedStores() {
        let stores = container.persistentStoreCoordinator.persistentStores
        if cloudKitEnabled {
            privateStore = stores.first { store in
                store.url?.lastPathComponent == "private.sqlite"
            }
            sharedStore = stores.first { store in
                store.url?.lastPathComponent == "shared.sqlite"
            }
        } else {
            privateStore = stores.first
            sharedStore = nil
        }
    }

    private func startObservingRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] notification in
            self?.consumePersistentHistory(for: notification)
        }
    }

    private func consumePersistentHistory(for notification: Notification) {
        guard let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String,
              let store = container.persistentStoreCoordinator.persistentStores.first(where: {
                  $0.identifier == storeUUID
              }) else { return }

        let backgroundContext = container.newBackgroundContext()
        backgroundContext.perform { [weak self] in
            guard let self else { return }
            let token = self.stateLock.scudderWithLock { self.historyTokens[storeUUID] }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            request.affectedStores = [store]
            guard let result = try? backgroundContext.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }

            self.stateLock.scudderWithLock { self.historyTokens[storeUUID] = transactions.last?.token }
            self.container.viewContext.perform {
                transactions.forEach {
                    self.container.viewContext.mergeChanges(fromContextDidSave: $0.objectIDNotification())
                }
            }
        }
    }

    private func publishShareStatus(_ message: String) {
        DispatchQueue.main.async { self.shareStatusMessage = message }
    }

    private static func makeStoreDescriptions(
        inMemory: Bool,
        cloudKitEnabled: Bool
    ) -> [NSPersistentStoreDescription] {
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.shouldAddStoreAsynchronously = false
            return [description]
        }

        let baseURL = NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("Food", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if !cloudKitEnabled {
            let description = NSPersistentStoreDescription(
                url: baseURL.appendingPathComponent("local.sqlite")
            )
            configureCommonOptions(description)
            return [description]
        }

        let privateDescription = NSPersistentStoreDescription(
            url: baseURL.appendingPathComponent("private.sqlite")
        )
        let privateOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions
        configureCommonOptions(privateDescription)

        let sharedDescription = NSPersistentStoreDescription(
            url: baseURL.appendingPathComponent("shared.sqlite")
        )
        let sharedOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions
        configureCommonOptions(sharedDescription)

        return [privateDescription, sharedDescription]
    }

    private static func configureCommonOptions(_ description: NSPersistentStoreDescription) {
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
    }
}

private extension NSLock {
    func scudderWithLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}
