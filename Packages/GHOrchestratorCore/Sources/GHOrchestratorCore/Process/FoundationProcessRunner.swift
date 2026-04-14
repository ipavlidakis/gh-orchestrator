import Foundation

public struct FoundationProcessRunner: ProcessRunner {
    private let processWrapperURL = URL(fileURLWithPath: "/usr/bin/env")

    public init() {}

    public func run(_ command: ProcessCommand) throws -> ProcessOutput {
        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let standardOutputCollector = DataCollector()
        let standardErrorCollector = DataCollector()

        process.executableURL = processWrapperURL
        process.arguments = [command.command] + command.arguments
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.environment = Self.resolvedEnvironment(from: command.environment)
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

    private static func resolvedEnvironment(from environment: [String: String]?) -> [String: String]? {
        guard let environment else {
            return nil
        }

        var merged = ProcessInfo.processInfo.environment
        environment.forEach { merged[$0.key] = $0.value }
        return merged
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

