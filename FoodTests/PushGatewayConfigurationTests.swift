import XCTest
@testable import Food

final class PushGatewayConfigurationTests: XCTestCase {
    func testEmptyURLDisablesConfiguration() {
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "",
            "PUSH_GATEWAY_APPLICATION_ID": "food",
        ]))
    }

    func testMissingURLDisablesConfiguration() {
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_APPLICATION_ID": "food",
        ]))
    }

    func testMalformedURLDisablesConfiguration() {
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "not a gateway URL",
            "PUSH_GATEWAY_APPLICATION_ID": "food",
        ]))
    }

    func testUnsupportedURLSchemeDisablesConfiguration() {
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "ftp://push.example.com",
            "PUSH_GATEWAY_APPLICATION_ID": "food",
        ]))
    }

    func testMissingOrInvalidApplicationIDDisablesConfiguration() {
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "https://push.example.com",
        ]))
        XCTAssertNil(PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "https://push.example.com",
            "PUSH_GATEWAY_APPLICATION_ID": "Food App",
        ]))
    }

    func testValidConfigurationParsesExactly() {
        let configuration = PushGatewayConfiguration.from(infoDictionary: [
            "PUSH_GATEWAY_URL": "https://push.example.com/staging/",
            "PUSH_GATEWAY_APPLICATION_ID": "food",
        ])

        XCTAssertEqual(configuration?.baseURL.absoluteString, "https://push.example.com/staging/")
        XCTAssertEqual(configuration?.applicationID, "food")
    }

    func testInstallationIDIsStableLowercaseAndReplacesCorruptText() throws {
        let store = InMemoryPushInstallationIDStore()
        let provider = KeychainPushInstallationIDProvider(store: store)

        let first = try provider.installationID()
        XCTAssertEqual(try provider.installationID(), first)
        XCTAssertEqual(store.lastAccount, "push-gateway.installation-id")
        XCTAssertEqual(store.value, first.uuidString.lowercased())

        store.value = "corrupt"
        let replacement = try provider.installationID()
        XCTAssertNotEqual(replacement, first)
        XCTAssertEqual(store.value, replacement.uuidString.lowercased())
    }

    func testInstallationIDStorageFailureIsSurfaced() {
        let store = InMemoryPushInstallationIDStore()
        store.error = TestInstallationStoreError.unavailable
        let provider = KeychainPushInstallationIDProvider(store: store)

        XCTAssertThrowsError(try provider.installationID()) { error in
            XCTAssertEqual(error as? TestInstallationStoreError, .unavailable)
        }
    }
}

private enum TestInstallationStoreError: Error, Equatable {
    case unavailable
}

private final class InMemoryPushInstallationIDStore: PushInstallationIDStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: String?
    private var storedAccount: String?
    private var storedError: Error?

    var value: String? {
        get { withLock { storedValue } }
        set { withLock { storedValue = newValue } }
    }

    var lastAccount: String? {
        withLock { storedAccount }
    }

    var error: Error? {
        get { withLock { storedError } }
        set { withLock { storedError = newValue } }
    }

    func read(account: String) throws -> String? {
        try withLock {
            storedAccount = account
            if let storedError { throw storedError }
            return storedValue
        }
    }

    func write(_ value: String, account: String) throws {
        try withLock {
            storedAccount = account
            if let storedError { throw storedError }
            storedValue = value
        }
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
