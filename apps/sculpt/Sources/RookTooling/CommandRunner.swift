import Foundation

struct CommandInvocation: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let directory: URL
}

struct CommandResult: Sendable {
    let status: Int32
    let output: Data
    let error: Data

    func writeOutput() {
        FileHandle.standardOutput.write(output)
        FileHandle.standardError.write(error)
    }
}

protocol CommandRunning: Sendable {
    func run(_ invocation: CommandInvocation) async throws -> CommandResult
}

struct SystemCommandRunner: CommandRunning {
    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        try await Task.detached {
            let manager = FileManager.default
            let directory = manager.temporaryDirectory.appendingPathComponent("rook-tool-\(UUID().uuidString)")
            try manager.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: directory) }

            let output = directory.appendingPathComponent("stdout")
            let error = directory.appendingPathComponent("stderr")
            manager.createFile(atPath: output.path, contents: nil)
            manager.createFile(atPath: error.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: output)
            let errorHandle = try FileHandle(forWritingTo: error)
            defer {
                try? outputHandle.close()
                try? errorHandle.close()
            }

            let process = Process()
            process.executableURL = invocation.executable
            process.arguments = invocation.arguments
            process.currentDirectoryURL = invocation.directory
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            try process.run()
            process.waitUntilExit()

            return try CommandResult(
                status: process.terminationStatus,
                output: Data(contentsOf: output),
                error: Data(contentsOf: error)
            )
        }.value
    }
}
