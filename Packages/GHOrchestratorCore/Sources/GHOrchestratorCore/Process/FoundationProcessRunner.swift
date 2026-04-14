import Foundation

public struct FoundationProcessRunner: ProcessRunner {
    private static let defaultFallbackSearchPaths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
    ]

    private let fallbackSearchPaths: [String]

    public init() {
        self.fallbackSearchPaths = Self.defaultFallbackSearchPaths
    }

    init(fallbackSearchPaths: [String]) {
        self.fallbackSearchPaths = fallbackSearchPaths
    }

    public func run(_ command: ProcessCommand) throws -> ProcessOutput {
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let standardOutputCollector = DataCollector()
        let standardErrorCollector = DataCollector()
        let environment = Self.resolvedEnvironment(
            from: command.environment,
            fallbackSearchPaths: fallbackSearchPaths
        )

        guard let executableURL = Self.resolveExecutableURL(
            for: command.command,
            environment: environment,
            fallbackSearchPaths: fallbackSearchPaths
        ) else {
            throw ProcessRunnerError.executableNotFound(command: command.command)
        }

        process.executableURL = executableURL
        process.arguments = command.arguments
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.environment = environment
        process.currentDirectoryURL = command.currentDirectoryURL

        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            standardOutputCollector.append(data)
        }

        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            standardErrorCollector.append(data)
        }

        do {
            try process.run()
        } catch {
            standardOutputPipe.fileHandleForReading.readabilityHandler = nil
            standardErrorPipe.fileHandleForReading.readabilityHandler = nil

            if Self.isMissingExecutableError(error) {
                throw ProcessRunnerError.executableNotFound(command: command.command)
            }

            throw ProcessRunnerError.launchFailure(
                command: command.command,
                message: error.localizedDescription
            )
        }

        process.waitUntilExit()

        standardOutputPipe.fileHandleForReading.readabilityHandler = nil
        standardErrorPipe.fileHandleForReading.readabilityHandler = nil

        let standardOutputData = standardOutputCollector.data + standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardErrorData = standardErrorCollector.data + standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessOutput(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: standardOutputData, as: UTF8.self),
            standardError: String(decoding: standardErrorData, as: UTF8.self)
        )
    }

    private static func resolvedEnvironment(
        from environment: [String: String]?,
        fallbackSearchPaths: [String]
    ) -> [String: String] {
        var merged = ProcessInfo.processInfo.environment
        environment?.forEach { merged[$0.key] = $0.value }
        merged["PATH"] = mergedPATH(
            existingPath: merged["PATH"],
            fallbackSearchPaths: fallbackSearchPaths
        )
        return merged
    }

    private static func mergedPATH(existingPath: String?, fallbackSearchPaths: [String]) -> String {
        var components = (existingPath ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for path in fallbackSearchPaths where !components.contains(path) {
            components.append(path)
        }

        return components.joined(separator: ":")
    }

    private static func resolveExecutableURL(
        for command: String,
        environment: [String: String],
        fallbackSearchPaths: [String]
    ) -> URL? {
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command)
                ? URL(fileURLWithPath: command)
                : nil
        }

        let searchPaths = mergedPATH(
            existingPath: environment["PATH"],
            fallbackSearchPaths: fallbackSearchPaths
        )
            .split(separator: ":")
            .map(String.init)

        for searchPath in searchPaths {
            let candidate = URL(fileURLWithPath: searchPath, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)

            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func isMissingExecutableError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain, nsError.code == 260 {
            return true
        }

        if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("no such file or directory") || message.contains("couldn't be launched")
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
