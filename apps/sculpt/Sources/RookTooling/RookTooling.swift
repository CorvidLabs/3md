import Foundation

/// Development operations are kept outside the application dependency graph.
public enum ToolingCommand: String, CaseIterable, Sendable {
    case format
    case intent
    case spec
    case boundaries
    case releaseFixture = "release-fixture"
    case package
    case run
    case build
}

public enum ToolingError: Error, CustomStringConvertible, Sendable {
    case unexpectedArguments(ToolingCommand)
    case missingFile(String)
    case versionMismatch(tool: String, expected: String, actual: String)
    case forbiddenSource(path: String, token: String)
    case toolingDependency(target: String)
    case invalidPackageDescription
    case invalidFileInventory
    case nonSwiftProgram(String)
    case releaseMarker(String)
    case unsafeBundle(String)
    /// The entitlements file at the path is not a property list dictionary.
    case invalidEntitlements(String)
    /// The entitlements file at the path holds a key outside the required set.
    case unexpectedEntitlement(path: String, key: String)
    /// The entitlements file at the path does not set the required key to a Boolean true.
    case requiredEntitlement(path: String, key: String)
    /// The product source at the path names a stored defaults key other than `rook.appearance`.
    case storedDefaultsKey(path: String, key: String)

    public var description: String {
        switch self {
        case .unexpectedArguments(let command):
            return "Unexpected arguments for \(command.rawValue)."
        case .missingFile(let path):
            return "Required file is missing: \(path)."
        case .versionMismatch(let tool, let expected, let actual):
            return "Refusing \(tool); expected \(expected), received \(actual)."
        case .forbiddenSource(let path, let token):
            return "Product source \(path) contains forbidden token \(token)."
        case .toolingDependency(let target):
            return "Product target \(target) depends on development tooling."
        case .invalidPackageDescription:
            return "The Swift package description could not be validated."
        case .invalidFileInventory:
            return "The repository file inventory could not be validated."
        case .nonSwiftProgram(let path):
            return "Repository-owned development programs must use Swift: \(path)."
        case .releaseMarker(let marker):
            return "The release executable contains development fixture \(marker)."
        case .unsafeBundle(let path):
            return "Refusing to replace an unrecognized or symbolic-link bundle at \(path)."
        case .invalidEntitlements(let path):
            return "Entitlements file \(path) is not a property list dictionary."
        case .unexpectedEntitlement(let path, let key):
            return "Entitlements file \(path) contains unexpected key \(key)."
        case .requiredEntitlement(let path, let key):
            return "Entitlements file \(path) must set \(key) to true."
        case .storedDefaultsKey(let path, let key):
            return "Product source \(path) uses stored defaults key \(key); only rook.appearance is allowed."
        }
    }
}

public enum RookTooling {
    /// Returns a child tool's failure status instead of turning it into success.
    public static func run(
        command: ToolingCommand,
        arguments: [String] = [],
        workingDirectory: URL
    ) async throws -> Int32 {
        try await NativeTools(
            runner: SystemCommandRunner(),
            environment: ProcessInfo.processInfo.environment
        ).run(command: command, arguments: arguments, root: workingDirectory)
    }
}

struct NativeTools: Sendable {
    let runner: any CommandRunning
    let environment: [String: String]

    func run(command: ToolingCommand, arguments: [String], root: URL) async throws -> Int32 {
        if ![.spec, .run, .build].contains(command), !arguments.isEmpty {
            throw ToolingError.unexpectedArguments(command)
        }

        switch command {
        case .format:
            let executable = URL(fileURLWithPath: "/opt/homebrew/bin/swift-format")
            try await requireVersion(executable, expected: "604.0.0", root: root)
            return try await execute(
                executable,
                arguments: ["lint", "--strict", "--recursive", "Sources", "Tests", "Package.swift"],
                root: root
            )
        case .intent:
            let executable = URL(fileURLWithPath: environment["ROOK_HI"] ?? "/tmp/rook-tools/hi")
            try await requireVersion(executable, expected: "hi 0.8.0", root: root)
            return try await execute(executable, arguments: ["check"], root: root)
        case .spec:
            let executable = URL(
                fileURLWithPath: environment["ROOK_SPECSYNC"]
                    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/specsync")
                    .path
            )
            try await requireVersion(executable, expected: "specsync 6.0.0", root: root)
            return try await execute(executable, arguments: ["check", "--strict"] + arguments, root: root)
        case .boundaries:
            try SourceBoundaries.validateSources(in: root)
            try SourceBoundaries.validateEntitlements(in: root)
            try await requireSwift(root: root)
            // Boundary checks also run inside SwiftPM tests, which hold their
            // build directory lock until the test process exits.
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(
                "rook-boundaries-\(UUID().uuidString)"
            )
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let result = try await runner.run(
                CommandInvocation(
                    executable: swift,
                    arguments: ["package", "--scratch-path", scratch.path, "dump-package"],
                    directory: root
                )
            )
            guard result.status == 0 else {
                result.writeOutput()
                return result.status
            }
            try SourceBoundaries.validatePackage(result.output)
            let inventory = try await runner.run(
                CommandInvocation(
                    executable: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                    directory: root
                )
            )
            guard inventory.status == 0 else {
                inventory.writeOutput()
                return inventory.status
            }
            try SourceBoundaries.validateFileInventory(inventory.output)
            print("source boundary scan passed; product targets exclude development tooling")
            return 0
        case .releaseFixture:
            let status = try await build(configuration: "release", arguments: [], root: root)
            guard status == 0 else { return status }
            let binary = root.appendingPathComponent(".build/release/Rook")
            try requireFile(binary)
            try ReleaseFixture.validate(Data(contentsOf: binary))
            print("release fixture strings are absent")
            return 0
        case .package:
            let status = try await build(configuration: "release", arguments: [], root: root)
            guard status == 0 else { return status }
            return try await AppPackaging(runner: runner).package(root: root)
        case .run:
            let bundle = root.appendingPathComponent("dist/Rook.app")
            if !FileManager.default.fileExists(atPath: bundle.path) {
                let status = try await run(command: .package, arguments: [], root: root)
                guard status == 0 else { return status }
            }
            try AppPackaging.validateOwnedBundle(bundle)
            return try await execute(
                URL(fileURLWithPath: "/usr/bin/open"),
                arguments: [bundle.path] + arguments,
                root: root
            )
        case .build:
            return try await build(configuration: "debug", arguments: arguments, root: root)
        }
    }

    private var swift: URL { URL(fileURLWithPath: "/usr/bin/swift") }

    private func requireSwift(root: URL) async throws {
        try await requireVersion(swift, expected: "Apple Swift version 6.3.3", root: root, contains: true)
    }

    private func requireVersion(
        _ executable: URL,
        expected: String,
        root: URL,
        contains: Bool = false
    ) async throws {
        let result = try await runner.run(
            CommandInvocation(executable: executable, arguments: ["--version"], directory: root)
        )
        let actual = String(decoding: result.output + result.error, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = contains ? actual.contains(expected + " ") : actual == expected
        guard result.status == 0, matches else {
            throw ToolingError.versionMismatch(tool: executable.lastPathComponent, expected: expected, actual: actual)
        }
    }

    private func build(configuration: String, arguments: [String], root: URL) async throws -> Int32 {
        try await requireSwift(root: root)
        return try await execute(
            swift,
            arguments: ["build", "--product", "Rook", "--configuration", configuration] + arguments,
            root: root
        )
    }

    private func execute(_ executable: URL, arguments: [String], root: URL) async throws -> Int32 {
        let result = try await runner.run(
            CommandInvocation(executable: executable, arguments: arguments, directory: root)
        )
        result.writeOutput()
        return result.status
    }
}

func requireFile(_ file: URL) throws {
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw ToolingError.missingFile(file.path)
    }
}
