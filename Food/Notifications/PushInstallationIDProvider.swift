import Foundation
import Security

protocol PushInstallationIDProviding: Sendable {
    func installationID() throws -> UUID
}

protocol PushInstallationIDStoring: Sendable {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
}

struct KeychainPushInstallationIDProvider: PushInstallationIDProviding {
    static let account = "push-gateway.installation-id"

    private let store: any PushInstallationIDStoring

    init(store: any PushInstallationIDStoring = SecurityPushInstallationIDStore()) {
        self.store = store
    }

    func installationID() throws -> UUID {
        if let stored = try store.read(account: Self.account),
           let identifier = UUID(uuidString: stored) {
            return identifier
        }

        let identifier = UUID()
        try store.write(identifier.uuidString.lowercased(), account: Self.account)
        return identifier
    }
}

struct SecurityPushInstallationIDStore: PushInstallationIDStoring {
    private let service: String

    init(service: String = "org.thescudders.food.push-gateway") {
        self.service = service
    }

    func read(account: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PushInstallationIDError.keychain(status)
        }
        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw PushInstallationIDError.invalidStoredValue
        }
        return value
    }

    func write(_ value: String, account: String) throws {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PushInstallationIDError.keychain(updateStatus)
        }

        var insert = query
        for (key, value) in attributes {
            insert[key] = value
        }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PushInstallationIDError.keychain(addStatus)
        }
    }
}

enum PushInstallationIDError: Error, Equatable {
    case invalidStoredValue
    case keychain(OSStatus)
}
