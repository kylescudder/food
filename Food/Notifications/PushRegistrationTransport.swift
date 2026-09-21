import Foundation

struct PushIdentity: Equatable, Sendable {
    let principalID: String
    let accessToken: String
}

enum APNSEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

protocol PushRegistrationTransport: Sendable {
    func register(
        installationID: UUID,
        deviceToken: Data,
        environment: APNSEnvironment,
        identity: PushIdentity
    ) async throws

    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws
}

enum PushGatewayError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}
