import Foundation

struct PushGatewayConfiguration: Equatable, Sendable {
    let baseURL: URL
    let applicationID: String

    static var fromBundle: PushGatewayConfiguration? {
        from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static func from(infoDictionary: [String: Any]) -> PushGatewayConfiguration? {
        guard
            let rawURL = infoDictionary["PUSH_GATEWAY_URL"] as? String,
            !rawURL.isEmpty,
            let baseURL = URL(string: rawURL),
            ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""),
            baseURL.host != nil,
            let applicationID = infoDictionary["PUSH_GATEWAY_APPLICATION_ID"] as? String,
            applicationID.range(
                of: #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#,
                options: .regularExpression
            ) != nil
        else {
            return nil
        }

        return PushGatewayConfiguration(baseURL: baseURL, applicationID: applicationID)
    }
}
