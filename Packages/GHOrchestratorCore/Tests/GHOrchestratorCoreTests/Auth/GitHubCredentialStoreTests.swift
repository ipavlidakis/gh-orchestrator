import Foundation
import XCTest
@testable import GHOrchestratorCore

final class GitHubCredentialStoreTests: XCTestCase {
    func testInMemoryCredentialStoreRoundTripsAndDeletesSession() throws {
        let session = GitHubSession(
            accessToken: "access-token",
            tokenType: "bearer",
            scopes: ["repo"],
            username: "octocat"
        )
        let store = InMemoryCredentialStore()

        try store.saveSession(session)
        XCTAssertEqual(try store.loadSession(), session)

        try store.deleteSession()
        XCTAssertNil(try store.loadSession())
    }

    func testKeychainCredentialStoreRoundTripsThroughInjectedSeam() throws {
        let session = GitHubSession(
            accessToken: "access-token",
            tokenType: "bearer",
            scopes: ["repo", "workflow"],
            refreshToken: "refresh-token",
            username: "octocat"
        )
        let keychain = MockKeychainDataStore()
        let store = KeychainGitHubCredentialStore(
            keychain: keychain,
            service: "test.service",
            account: "test.account",
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )

        try store.saveSession(session)

        XCTAssertEqual(keychain.lastWriteService, "test.service")
        XCTAssertEqual(keychain.lastWriteAccount, "test.account")
        XCTAssertEqual(try store.loadSession(), session)
    }

    func testKeychainCredentialStoreReturnsNilWhenSessionIsMissing() throws {
        let store = KeychainGitHubCredentialStore(
            keychain: MockKeychainDataStore(),
            service: "test.service",
            account: "test.account",
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )

        XCTAssertNil(try store.loadSession())
    }

    func testKeychainCredentialStoreThrowsDecodingErrorForCorruptData() {
        let keychain = MockKeychainDataStore()
        keychain.storedData = Data("not-json".utf8)
        let store = KeychainGitHubCredentialStore(
            keychain: keychain,
            service: "test.service",
            account: "test.account",
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )

        XCTAssertThrowsError(try store.loadSession()) { error in
            guard case .decodingFailed(let message) = error as? GitHubCredentialStoreError else {
                return XCTFail("Expected decoding failure, got \(error)")
            }

            XCTAssertFalse(message.isEmpty)
        }
    }
}

private final class InMemoryCredentialStore: GitHubCredentialStore, @unchecked Sendable {
    private var session: GitHubSession?

    func loadSession() throws -> GitHubSession? {
        session
    }

    func saveSession(_ session: GitHubSession) throws {
        self.session = session
    }

    func deleteSession() throws {
        session = nil
    }
}

private final class MockKeychainDataStore: KeychainDataStore, @unchecked Sendable {
    var storedData: Data?
    var lastWriteService: String?
    var lastWriteAccount: String?
    var lastDeleteService: String?
    var lastDeleteAccount: String?

    func readData(service: String, account: String) throws -> Data? {
        XCTAssertEqual(service, lastWriteService ?? service)
        XCTAssertEqual(account, lastWriteAccount ?? account)
        return storedData
    }

    func writeData(_ data: Data, service: String, account: String) throws {
        storedData = data
        lastWriteService = service
        lastWriteAccount = account
    }

    func deleteData(service: String, account: String) throws {
        storedData = nil
        lastDeleteService = service
        lastDeleteAccount = account
    }
}
