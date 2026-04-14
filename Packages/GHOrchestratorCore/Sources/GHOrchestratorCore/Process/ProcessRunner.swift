import Foundation

public protocol ProcessRunner: Sendable {
    func run(_ command: ProcessCommand) throws -> ProcessOutput
}

