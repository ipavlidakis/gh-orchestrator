import Foundation
import Security

public protocol GitHubCredentialStore: Sendable {
    func loadSession() throws -> GitHubSession?
    func saveSession(_ session: GitHubSession) throws
    func deleteSession() throws
}

public struct KeychainGitHubCredentialStore: GitHubCredentialStore {
    public static let defaultService = "GHOrchestrator.github.com"
    public static let defaultAccount = "oauth-session"

    private let keychain: any KeychainDataStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let service: String
    private let account: String

    public init(
        service: String = KeychainGitHubCredentialStore.defaultService,
        account: String = KeychainGitHubCredentialStore.defaultAccount
    ) {
        self.init(
            keychain: SecurityKeychainDataStore(),
            service: service,
            account: account,
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )
    }

    init(
        keychain: any KeychainDataStore,
        service: String,
        account: String,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) {
        self.keychain = keychain
        self.service = service
        self.account = account
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadSession() throws -> GitHubSession? {
        guard let data = try keychain.readData(service: service, account: account) else {
            return nil
        }

        do {
            return try decoder.decode(GitHubSession.self, from: data)
        } catch {
            throw GitHubCredentialStoreError.decodingFailed(message: error.localizedDescription)
        }
    }

    public func saveSession(_ session: GitHubSession) throws {
        let data: Data

        do {
            data = try encoder.encode(session)
        } catch {
            throw GitHubCredentialStoreError.encodingFailed(message: error.localizedDescription)
        }

        try keychain.writeData(data, service: service, account: account)
    }

    public func deleteSession() throws {
        try keychain.deleteData(service: service, account: account)
    }
}

public enum GitHubCredentialStoreError: Equatable, LocalizedError, Sendable {
    case encodingFailed(message: String)
    case decodingFailed(message: String)
    case keychainFailure(operation: String, status: Int32)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let message):
            return "Unable to encode the GitHub session for secure storage: \(message)"
        case .decodingFailed(let message):
            return "Unable to decode the stored GitHub session from Keychain: \(message)"
        case .keychainFailure(let operation, let status):
            return "Keychain \(operation) failed with OSStatus \(status)."
        }
    }
}

protocol KeychainDataStore: Sendable {
    func readData(service: String, account: String) throws -> Data?
    func writeData(_ data: Data, service: String, account: String) throws
    func deleteData(service: String, account: String) throws
}

struct SecurityKeychainDataStore: KeychainDataStore {
    func readData(service: String, account: String) throws -> Data? {
        let query = keychainQuery(service: service, account: account)
            .merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, newValue in
                newValue
            }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw GitHubCredentialStoreError.keychainFailure(operation: "read", status: status)
        }
    }

    func writeData(_ data: Data, service: String, account: String) throws {
        let query = keychainQuery(service: service, account: account)
        let attributesToUpdate = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data

            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GitHubCredentialStoreError.keychainFailure(operation: "write", status: addStatus)
            }
        default:
            throw GitHubCredentialStoreError.keychainFailure(operation: "write", status: updateStatus)
        }
    }

    func deleteData(service: String, account: String) throws {
        let status = SecItemDelete(keychainQuery(service: service, account: account) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCredentialStoreError.keychainFailure(operation: "delete", status: status)
        }
    }

    private func keychainQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
