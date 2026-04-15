import AppKit
import CryptoKit
import Foundation
import GHOrchestratorCore

@MainActor
protocol SoftwareUpdateInstalling {
    func install(_ update: SoftwareUpdate) async throws
}

@MainActor
final class DMGSoftwareUpdateInstaller: SoftwareUpdateInstalling {
    private let session: URLSession
    private let fileManager: FileManager
    private let processRunner: any ProcessRunner
    private let application: NSApplication
    private let bundleURLProvider: () -> URL
    private let processIDProvider: () -> Int32

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        processRunner: any ProcessRunner = FoundationProcessRunner(),
        application: NSApplication? = nil,
        bundleURLProvider: @escaping () -> URL = { Bundle.main.bundleURL },
        processIDProvider: @escaping () -> Int32 = { getpid() }
    ) {
        self.session = session
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.application = application ?? .shared
        self.bundleURLProvider = bundleURLProvider
        self.processIDProvider = processIDProvider
    }

    func install(_ update: SoftwareUpdate) async throws {
        let workDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("GHOrchestratorUpdate-\(UUID().uuidString)", isDirectory: true)
        let dmgURL = workDirectoryURL.appendingPathComponent(update.downloadAsset.name, isDirectory: false)
        let checksumURL = workDirectoryURL.appendingPathComponent(update.checksumAsset.name, isDirectory: false)
        let mountPointURL = workDirectoryURL.appendingPathComponent("mount", isDirectory: true)

        do {
            try fileManager.createDirectory(at: workDirectoryURL, withIntermediateDirectories: true)
            try await download(update.downloadAsset.url, to: dmgURL)
            try await download(update.checksumAsset.url, to: checksumURL)
            try verifyChecksum(dmgURL: dmgURL, checksumURL: checksumURL)
            try fileManager.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
            try runRequired(
                ProcessCommand(
                    command: "hdiutil",
                    arguments: [
                        "attach",
                        dmgURL.path,
                        "-nobrowse",
                        "-readonly",
                        "-mountpoint",
                        mountPointURL.path,
                    ]
                )
            )

            let sourceAppURL = mountPointURL.appendingPathComponent("\(AppMetadata.menuBarTitle).app", isDirectory: true)
            guard fileManager.fileExists(atPath: sourceAppURL.path) else {
                throw SoftwareUpdateInstallError.missingMountedApp(sourceAppURL.path)
            }

            let targetAppURL = bundleURLProvider()
            guard targetAppURL.pathExtension == "app" else {
                throw SoftwareUpdateInstallError.invalidCurrentAppBundle(targetAppURL.path)
            }

            let targetParentURL = targetAppURL.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: targetParentURL.path) else {
                throw SoftwareUpdateInstallError.targetDirectoryNotWritable(targetParentURL.path)
            }

            let helperURL = workDirectoryURL.appendingPathComponent("install-update.zsh", isDirectory: false)
            try installerScript().write(to: helperURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: helperURL.path
            )

            try launchHelper(
                helperURL: helperURL,
                sourceAppURL: sourceAppURL,
                targetAppURL: targetAppURL,
                mountPointURL: mountPointURL,
                workDirectoryURL: workDirectoryURL
            )
            application.terminate(nil)
        } catch {
            try? detach(mountPointURL: mountPointURL)
            try? fileManager.removeItem(at: workDirectoryURL)
            throw error
        }
    }

    private func download(_ sourceURL: URL, to destinationURL: URL) async throws {
        let temporaryURL: URL
        let response: URLResponse

        do {
            (temporaryURL, response) = try await session.download(from: sourceURL)
        } catch {
            throw SoftwareUpdateInstallError.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw SoftwareUpdateInstallError.downloadFailed(
                "Download failed with status code \(httpResponse.statusCode)."
            )
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func verifyChecksum(dmgURL: URL, checksumURL: URL) throws {
        let expected = try expectedSHA256(from: checksumURL)
        let actual = try sha256(for: dmgURL)

        guard expected == actual else {
            throw SoftwareUpdateInstallError.checksumMismatch
        }
    }

    private func expectedSHA256(from url: URL) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        let token = text
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)?
            .lowercased()

        guard let token,
              token.count == 64,
              token.allSatisfy({ $0.isHexDigit })
        else {
            throw SoftwareUpdateInstallError.invalidChecksumFile
        }

        return token
    }

    private func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else {
                break
            }

            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func runRequired(_ command: ProcessCommand) throws {
        let output = try processRunner.run(command)
        guard output.exitCode == 0 else {
            let message = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SoftwareUpdateInstallError.commandFailed(
                command.command,
                message.isEmpty ? output.standardOutput : message
            )
        }
    }

    private func detach(mountPointURL: URL) throws {
        guard fileManager.fileExists(atPath: mountPointURL.path) else {
            return
        }

        try runRequired(
            ProcessCommand(
                command: "hdiutil",
                arguments: ["detach", mountPointURL.path, "-quiet"]
            )
        )
    }

    private func launchHelper(
        helperURL: URL,
        sourceAppURL: URL,
        targetAppURL: URL,
        mountPointURL: URL,
        workDirectoryURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh", isDirectory: false)
        process.arguments = [
            helperURL.path,
            "\(processIDProvider())",
            sourceAppURL.path,
            targetAppURL.path,
            mountPointURL.path,
            workDirectoryURL.path,
        ]
        try process.run()
    }

    private func installerScript() -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        app_pid="$1"
        source_app="$2"
        target_app="$3"
        mount_point="$4"
        work_dir="$5"
        target_parent="$(/usr/bin/dirname "$target_app")"
        staged_app="${target_app}.update"

        while /bin/kill -0 "$app_pid" 2>/dev/null; do
          /bin/sleep 0.2
        done

        if [[ ! -d "$source_app" ]]; then
          /usr/bin/hdiutil detach "$mount_point" -quiet || true
          exit 66
        fi

        if [[ ! -w "$target_parent" ]]; then
          /usr/bin/hdiutil detach "$mount_point" -quiet || true
          exit 73
        fi

        /bin/rm -rf "$staged_app"
        /usr/bin/ditto "$source_app" "$staged_app"
        /bin/rm -rf "$target_app"
        /bin/mv "$staged_app" "$target_app"
        /usr/bin/hdiutil detach "$mount_point" -quiet || true
        /usr/bin/open -n "$target_app"
        /bin/rm -rf "$work_dir"
        """
    }
}

enum SoftwareUpdateInstallError: Error, Equatable, LocalizedError {
    case downloadFailed(String)
    case invalidChecksumFile
    case checksumMismatch
    case missingMountedApp(String)
    case invalidCurrentAppBundle(String)
    case targetDirectoryNotWritable(String)
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Update download failed: \(message)"
        case .invalidChecksumFile:
            return "The update checksum file is not valid."
        case .checksumMismatch:
            return "The downloaded update did not match the release checksum."
        case .missingMountedApp(let path):
            return "The mounted update did not contain GHOrchestrator at \(path)."
        case .invalidCurrentAppBundle(let path):
            return "The current app bundle is not installable: \(path)."
        case .targetDirectoryNotWritable(let path):
            return "GHOrchestrator cannot replace the app in \(path). Move it to a writable Applications folder and try again."
        case .commandFailed(let command, let message):
            return "\(command) failed: \(message)"
        }
    }
}
