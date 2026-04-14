import Foundation

public struct GitHubDeviceAuthorizationRequest: Equatable, Sendable {
    public let clientID: String
    public let scope: String

    public init(
        clientID: String,
        scopes: [String]
    ) {
        self.clientID = clientID
        self.scope = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func formURLEncodedData() -> Data {
        var queryItems = [URLQueryItem(name: "client_id", value: clientID)]

        if !scope.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scope))
        }

        let payload = queryItems
            .map { item in
                let value = item.value ?? ""
                return "\(item.name.percentEncodedQueryValue)=\(value.percentEncodedQueryValue)"
            }
            .joined(separator: "&")

        return Data(payload.utf8)
    }
}

public struct GitHubDeviceAuthorization: Codable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int

    public init(
        deviceCode: String,
        userCode: String,
        verificationURI: URL,
        expiresIn: Int,
        interval: Int
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = max(interval, 1)
    }

    public func expirationDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(max(expiresIn, 0)))
    }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct GitHubDeviceAccessTokenPollRequest: Equatable, Sendable {
    public static let deviceCodeGrantType = "urn:ietf:params:oauth:grant-type:device_code"

    public let clientID: String
    public let deviceCode: String
    public let grantType: String

    public init(
        clientID: String,
        deviceCode: String,
        grantType: String = GitHubDeviceAccessTokenPollRequest.deviceCodeGrantType
    ) {
        self.clientID = clientID
        self.deviceCode = deviceCode
        self.grantType = grantType
    }

    func formURLEncodedData() -> Data {
        let queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "device_code", value: deviceCode),
            URLQueryItem(name: "grant_type", value: grantType),
        ]

        let payload = queryItems
            .map { item in
                let value = item.value ?? ""
                return "\(item.name.percentEncodedQueryValue)=\(value.percentEncodedQueryValue)"
            }
            .joined(separator: "&")

        return Data(payload.utf8)
    }
}

public enum GitHubDeviceAuthorizationPollResult: Equatable, Sendable {
    case pending(nextInterval: Int)
    case success(GitHubSession)
}

public enum GitHubDeviceAuthorizationError: Equatable, LocalizedError, Sendable {
    case accessDenied(description: String?, documentationURL: URL?)
    case expiredToken
    case deviceFlowDisabled
    case incorrectClientCredentials
    case incorrectDeviceCode
    case unsupportedGrantType
    case authorizationFailed(error: String, description: String?, documentationURL: URL?)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let description, let documentationURL):
            return Self.message(
                prefix: "GitHub sign-in was cancelled.",
                description: description,
                documentationURL: documentationURL
            )
        case .expiredToken:
            return "The GitHub device sign-in code expired. Start sign-in again."
        case .deviceFlowDisabled:
            return "GitHub device flow is not enabled for this OAuth app."
        case .incorrectClientCredentials:
            return "The configured GitHub OAuth client ID is invalid for device flow."
        case .incorrectDeviceCode:
            return "GitHub rejected the device authorization code. Start sign-in again."
        case .unsupportedGrantType:
            return "GitHub rejected the device-flow grant type."
        case .authorizationFailed(let error, let description, let documentationURL):
            return Self.message(
                prefix: "GitHub device authorization failed with \(error).",
                description: description,
                documentationURL: documentationURL
            )
        }
    }

    private static func message(
        prefix: String,
        description: String?,
        documentationURL: URL?
    ) -> String {
        let details = [description, documentationURL?.absoluteString]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !details.isEmpty else {
            return prefix
        }

        return "\(prefix) \(details)"
    }
}
