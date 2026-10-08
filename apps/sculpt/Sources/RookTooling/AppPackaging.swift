import Foundation

struct AppPackaging: Sendable {
    let runner: any CommandRunning

    func package(root: URL) async throws -> Int32 {
        let manager = FileManager.default
        let binary = root.appendingPathComponent(".build/release/Rook")
        let information = root.appendingPathComponent("App/Info.plist")
        let entitlements = root.appendingPathComponent("App/Rook.entitlements")
        try [binary, information, entitlements].forEach { try requireFile($0) }

        let distribution = root.appendingPathComponent("dist")
        try Self.rejectSymbolicLink(distribution)
        try manager.createDirectory(at: distribution, withIntermediateDirectories: true)
        let destination = distribution.appendingPathComponent("Rook.app")
        if manager.fileExists(atPath: destination.path) { try Self.validateOwnedBundle(destination) }

        let staging = distribution.appendingPathComponent(".rook-package-\(UUID().uuidString).app")
        try manager.createDirectory(
            at: staging.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: binary, to: staging.appendingPathComponent("Contents/MacOS/Rook"))
        try manager.copyItem(at: information, to: staging.appendingPathComponent("Contents/Info.plist"))
        try Self.validateOwnedBundle(staging)

        let signature = try await runner.run(
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--force", "--sign", "-", "--entitlements", entitlements.path, staging.path],
                directory: root
            )
        )
        signature.writeOutput()
        guard signature.status == 0 else { return signature.status }

        let verification = try await runner.run(
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--verify", "--strict", staging.path],
                directory: root
            )
        )
        verification.writeOutput()
        guard verification.status == 0 else { return verification.status }

        let display = try await runner.run(
            CommandInvocation(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--display", "--entitlements", "-", staging.path],
                directory: root
            )
        )
        display.writeOutput()
        guard display.status == 0 else { return display.status }

        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
        print("packaged \(destination.path); local ad-hoc signature, not notarized")
        return 0
    }

    static func validateOwnedBundle(_ bundle: URL) throws {
        try rejectSymbolicLink(bundle)
        let information = bundle.appendingPathComponent("Contents/Info.plist")
        try rejectSymbolicLink(bundle.appendingPathComponent("Contents"))
        try rejectSymbolicLink(information)
        let data = try Data(contentsOf: information)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            values["CFBundleIdentifier"] as? String == "labs.corvid.rook",
            values["CFBundleExecutable"] as? String == "Rook"
        else { throw ToolingError.unsafeBundle(bundle.path) }
    }

    private static func rejectSymbolicLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ToolingError.unsafeBundle(url.path)
        }
    }
}
