import Foundation

struct GatewayPushRegistrationTransport: PushRegistrationTransport {
    let configuration: PushGatewayConfiguration
    let session: URLSession

    init(
        configuration: PushGatewayConfiguration,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.configuration = configuration
        self.session = session
    }

    func register(
        installationID: UUID,
        deviceToken: Data,
        environment: APNSEnvironment,
        identity: PushIdentity
    ) async throws {
        let url = installationURL(installationID)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RegisterInstallationRequest(
            version: 1,
            platform: "ios",
            apnsToken: deviceToken.hexadecimalString,
            apnsEnvironment: environment
        ))

        let (_, response) = try await session.data(for: request)
        try Self.requireSuccess(response)
    }

    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws {
        let url = installationURL(installationID).appending(path: "account-link")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(identity.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        try Self.requireSuccess(response)
    }

    private func installationURL(_ installationID: UUID) -> URL {
        configuration.baseURL
            .appending(path: "v1/apps")
            .appending(path: configuration.applicationID)
            .appending(path: "installations")
            .appending(path: installationID.uuidString.lowercased())
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PushGatewayError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PushGatewayError.httpStatus(httpResponse.statusCode)
        }
    }
}

private struct RegisterInstallationRequest: Encodable {
    let version: Int
    let platform: String
    let apnsToken: String
    let apnsEnvironment: APNSEnvironment

    enum CodingKeys: String, CodingKey {
        case version
        case platform
        case apnsToken = "apns_token"
        case apnsEnvironment = "apns_environment"
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
