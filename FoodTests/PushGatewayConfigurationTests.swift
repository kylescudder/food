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
}
