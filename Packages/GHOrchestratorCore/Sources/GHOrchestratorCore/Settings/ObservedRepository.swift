public struct ObservedRepository: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let owner: String
    public let name: String

    public var id: String {
        normalizedLookupKey
    }

    public var fullName: String {
        "\(owner)/\(name)"
    }

    public var normalizedLookupKey: String {
        "\(owner.lowercased())/\(name.lowercased())"
    }

    public init(owner: String, name: String) {
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return nil
        }

        let owner = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard Self.isValidComponent(owner), Self.isValidComponent(name) else {
            return nil
        }

        self.init(owner: owner, name: name)
    }

    public static func parseList(from rawValue: String) -> ObservedRepositoryParseResult {
        let lines = rawValue.components(separatedBy: .newlines)

        var repositories: [ObservedRepository] = []
        var invalidEntries: [String] = []
        var seenKeys = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard let repository = ObservedRepository(rawValue: trimmed) else {
                invalidEntries.append(trimmed)
                continue
            }

            if seenKeys.insert(repository.normalizedLookupKey).inserted {
                repositories.append(repository)
            }
        }

        return ObservedRepositoryParseResult(
            repositories: repositories,
            invalidEntries: invalidEntries
        )
    }

    private static func isValidComponent(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        return !value.contains(where: \.isWhitespace) && !value.contains("/")
    }
}

public struct ObservedRepositoryParseResult: Equatable, Sendable {
    public let repositories: [ObservedRepository]
    public let invalidEntries: [String]

    public init(repositories: [ObservedRepository], invalidEntries: [String]) {
        self.repositories = repositories
        self.invalidEntries = invalidEntries
    }
}
