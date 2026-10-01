import Foundation

enum BoundedConcurrency {
    /// Default fan-out for GitHub requests. High enough to hide latency over HTTP/2,
    /// low enough to stay clear of GitHub's secondary (concurrency) rate limits.
    static let defaultLimit = 8

    /// Maps `items` with at most `limit` operations in flight, returning results in input order.
    /// The first thrown error cancels the remaining work and is rethrown.
    static func map<Item: Sendable, Result: Sendable>(
        _ items: [Item],
        limit: Int = defaultLimit,
        _ transform: @escaping @Sendable (Item) async throws -> Result
    ) async throws -> [Result] {
        guard !items.isEmpty else {
            return []
        }

        let width = max(min(limit, items.count), 1)

        return try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var nextIndex = 0

            func addNext() {
                let index = nextIndex
                let item = items[index]
                nextIndex += 1
                group.addTask { (index, try await transform(item)) }
            }

            while nextIndex < width {
                addNext()
            }

            var results: [(Int, Result)] = []
            results.reserveCapacity(items.count)

            while let result = try await group.next() {
                results.append(result)
                if nextIndex < items.count {
                    addNext()
                }
            }

            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
