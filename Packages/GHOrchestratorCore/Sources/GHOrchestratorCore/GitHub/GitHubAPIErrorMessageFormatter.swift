import Foundation

enum GitHubAPIErrorMessageFormatter {
    static func normalize(data: Data) -> String {
        if let envelope = decodeEnvelope(from: data) {
            let messages = [
                envelope.message,
                envelope.errorDescription,
                envelope.errors?.compactMap(\.message).joined(separator: " ")
            ]
                .compactMap { value in
                    value?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }

            if !messages.isEmpty {
                return deduplicated(messages).joined(separator: " ")
            }
        }

        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalize(_ rawMessage: String) -> String {
        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        let messages = trimmed
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap(extractMessages(from:))

        let deduplicatedMessages = deduplicated(messages)
        guard !deduplicatedMessages.isEmpty else {
            return trimmed
        }

        return deduplicatedMessages.joined(separator: " ")
    }

    private static func extractMessages(from line: String) -> [String] {
        guard !line.isEmpty else {
            return []
        }

        if let envelope = decodeEnvelope(from: line) {
            let nestedMessages = [
                envelope.message,
                envelope.errors?.compactMap(\.message).joined(separator: " ")
            ]
                .compactMap { value in
                    value?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }

            if !nestedMessages.isEmpty {
                return nestedMessages
            }
        }

        let stripped = line.replacingOccurrences(
            of: #"^gh:\s*"#,
            with: "",
            options: .regularExpression
        )

        let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? [] : [cleaned]
    }

    private static func deduplicated(_ messages: [String]) -> [String] {
        var seen = Set<String>()
        var orderedMessages: [String] = []

        for message in messages {
            let key = message
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !key.isEmpty, seen.insert(key).inserted else {
                continue
            }

            orderedMessages.append(message)
        }

        return orderedMessages
    }

    private static func decodeEnvelope(from line: String) -> GitHubAPIErrorEnvelope? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        return decodeEnvelope(from: data)
    }

    private static func decodeEnvelope(from data: Data) -> GitHubAPIErrorEnvelope? {
        try? JSONDecoder().decode(GitHubAPIErrorEnvelope.self, from: data)
    }
}

private struct GitHubAPIErrorEnvelope: Decodable {
    let message: String?
    let errorDescription: String?
    let errors: [GitHubAPIErrorItem]?

    enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
        case errors
    }
}

private struct GitHubAPIErrorItem: Decodable {
    let message: String?
}
