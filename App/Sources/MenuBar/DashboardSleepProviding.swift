import Foundation

protocol DashboardSleepProviding: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskSleepProvider: DashboardSleepProviding {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
