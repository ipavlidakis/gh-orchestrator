import CryptoKit
import Foundation

public struct OAuthCodeVerifier: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else {
            return nil
        }

        self.rawValue = rawValue
    }

    public static func generate() -> OAuthCodeVerifier {
        let data = randomData(byteCount: 32)
        return OAuthCodeVerifier(rawValue: data.base64URLEncodedString())!
    }

    public var codeChallenge: OAuthCodeChallenge {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        return OAuthCodeChallenge(rawValue: Data(digest).base64URLEncodedString())
    }

    private static func isValid(_ rawValue: String) -> Bool {
        guard (43...128).contains(rawValue.count) else {
            return false
        }

        return rawValue.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 46, 95, 126:
                return true
            case 48...57, 65...90, 97...122:
                return true
            default:
                return false
            }
        }
    }
}

public struct OAuthCodeChallenge: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct OAuthState: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        self.rawValue = normalized
    }

    public static func generate() -> OAuthState {
        OAuthState(rawValue: randomData(byteCount: 32).base64URLEncodedString())!
    }
}

private func randomData(byteCount: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<byteCount).map { _ in
        UInt8.random(in: .min ... .max, using: &generator)
    }

    return Data(bytes)
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
