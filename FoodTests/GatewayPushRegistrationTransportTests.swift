import XCTest
@testable import Food

final class GatewayPushRegistrationTransportTests: XCTestCase {
    private let installationID = UUID(uuidString: "550d5a6b-7248-49da-a4dc-92db45608c07")!
    private let identity = PushIdentity(
        principalID: "principal-must-not-be-sent",
        accessToken: "test-access-token"
    )

    override func tearDown() {
        URLProtocolStub.setHandler(nil)
        super.tearDown()
    }

    func testRegisterBuildsCanonicalRequestAndPreservesLeadingZeroTokenBytes() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.setHandler { request in
            recorder.record(request)
            return Self.httpResponse(for: request, statusCode: 204)
        }

        let transport = makeTransport(baseURL: "https://push.example.com/")
        try await transport.register(
            installationID: installationID,
            deviceToken: Data([0x00, 0x0a, 0xff]),
            environment: .sandbox,
            identity: identity
        )

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.absoluteString, "https://push.example.com/v1/apps/food/installations/550d5a6b-7248-49da-a4dc-92db45608c07")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["platform"] as? String, "ios")
        XCTAssertEqual(object["apns_token"] as? String, "000aff")
        XCTAssertEqual(object["apns_environment"] as? String, "sandbox")
        XCTAssertNil(object["principal_id"])
        XCTAssertNil(object["bundle_id"])
        XCTAssertNil(object["team_id"])
        XCTAssertNil(object["supabase_url"])
    }

    func testTrailingSlashDoesNotCreateDoubleSlash() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.setHandler { request in
            recorder.record(request)
            return Self.httpResponse(for: request, statusCode: 204)
        }

        try await makeTransport(baseURL: "https://push.example.com/root/").register(
            installationID: installationID,
            deviceToken: Data([0x01]),
            environment: .production,
            identity: identity
        )

        XCTAssertEqual(
            recorder.request?.url?.absoluteString,
            "https://push.example.com/root/v1/apps/food/installations/550d5a6b-7248-49da-a4dc-92db45608c07"
        )
    }

    func testUnregisterBuildsCanonicalRequestWithoutBodyOrDeviceToken() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.setHandler { request in
            recorder.record(request)
            return Self.httpResponse(for: request, statusCode: 204)
        }

        try await makeTransport().unregister(
            installationID: installationID,
            identity: identity
        )

        let request = try XCTUnwrap(recorder.request)
        XCTAssertEqual(request.url?.absoluteString, "https://push.example.com/v1/apps/food/installations/550d5a6b-7248-49da-a4dc-92db45608c07/account-link")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertNil(request.httpBody)
    }

    func testNonSuccessStatusIsTypedFailure() async throws {
        URLProtocolStub.setHandler { request in
            Self.httpResponse(for: request, statusCode: 503)
        }

        do {
            try await makeTransport().unregister(
                installationID: installationID,
                identity: identity
            )
            XCTFail("Expected an HTTP status error")
        } catch let error as PushGatewayError {
            XCTAssertEqual(error, .httpStatus(503))
        }
    }

    func testNonHTTPResponseIsTypedFailure() async throws {
        URLProtocolStub.setHandler { request in
            (URLResponse(
                url: try XCTUnwrap(request.url),
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            ), Data())
        }

        do {
            try await makeTransport().unregister(
                installationID: installationID,
                identity: identity
            )
            XCTFail("Expected an invalid response error")
        } catch let error as PushGatewayError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    private func makeTransport(
        baseURL: String = "https://push.example.com"
    ) -> GatewayPushRegistrationTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return GatewayPushRegistrationTransport(
            configuration: PushGatewayConfiguration(
                baseURL: URL(string: baseURL)!,
                applicationID: "food"
            ),
            session: URLSession(configuration: configuration)
        )
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int
    ) -> (URLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data())
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.withLock { storedRequest }
    }

    func record(_ request: URLRequest) {
        lock.withLock { storedRequest = request }
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private static let storage = URLProtocolHandlerStorage()

    static func setHandler(_ handler: URLProtocolHandlerStorage.Handler?) {
        storage.set(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.storage.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class URLProtocolHandlerStorage: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func set(_ handler: Handler?) {
        lock.withLock { self.handler = handler }
    }

    func response(for request: URLRequest) throws -> (URLResponse, Data) {
        let handler = lock.withLock { handler }
        guard let handler else { throw URLError(.badServerResponse) }
        return try handler(request)
    }
}
