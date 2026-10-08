import Foundation
import Testing

@testable import RookTooling

@Test func directProcessExecutionDoesNotInterpretArgumentText() async throws {
    let result = try await SystemCommandRunner().run(
        CommandInvocation(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "literal; $(never-executed) `also-literal`"],
            directory: FileManager.default.temporaryDirectory
        )
    )
    #expect(result.status == 0)
    #expect(String(decoding: result.output, as: UTF8.self) == "literal; $(never-executed) `also-literal`")
    #expect(result.error.isEmpty)
}

@Test func incorrectPinnedVersionStopsBeforeRunningTheTool() async throws {
    let runner = RecordingRunner(results: [.text("hi 0.8.01\n")])
    let tools = NativeTools(runner: runner, environment: ["ROOK_HI": "/tmp/owned-hi"])

    await #expect(throws: ToolingError.self) {
        try await tools.run(command: .intent, arguments: [], root: URL(fileURLWithPath: "/tmp"))
    }
    let invocations = await runner.invocations
    #expect(invocations.count == 1)
    #expect(invocations.first?.executable.path == "/tmp/owned-hi")
    #expect(invocations.first?.arguments == ["--version"])
}

@Test func specArgumentsRemainLiteralArgumentsAndFailuresPropagate() async throws {
    let runner = RecordingRunner(results: [.text("specsync 6.0.0\n"), .text("failed\n", status: 7)])
    let root = URL(fileURLWithPath: "/tmp/path with spaces")
    let arguments = ["--scope", "name; $(not-a-command)"]
    let tools = NativeTools(runner: runner, environment: ["ROOK_SPECSYNC": "/tmp/owned-specsync"])

    let status = try await tools.run(command: .spec, arguments: arguments, root: root)

    #expect(status == 7)
    let invocation = await runner.invocations.last
    #expect(invocation?.executable.path == "/tmp/owned-specsync")
    #expect(invocation?.directory == root)
    #expect(invocation?.arguments == ["check", "--strict"] + arguments)
}

@Test func failedReleaseBuildDoesNotScanAnOldExecutable() async throws {
    let runner = RecordingRunner(results: [.swiftVersion, .text("build failed", status: 12)])
    let tools = NativeTools(runner: runner, environment: [:])
    let root = URL(fileURLWithPath: "/tmp/no-release-executable")

    #expect(try await tools.run(command: .releaseFixture, arguments: [], root: root) == 12)
    let invocation = await runner.invocations.last
    #expect(invocation?.executable.path == "/usr/bin/swift")
    #expect(invocation?.arguments == ["build", "--product", "Rook", "--configuration", "release"])
}

@Test func failedPackagingReleaseBuildDoesNotCopyAnOldExecutableOrReplaceTheBundle() async throws {
    let fixture = try ToolingFixture(includePackagingInputs: true)
    defer { fixture.remove() }
    let destination = try fixture.existingBundle()
    let sentinel = destination.appendingPathComponent("existing-content")
    try Data("keep me".utf8).write(to: sentinel)
    let runner = RecordingRunner(results: [.swiftVersion, .text("release build failed", status: 12)])
    let tools = NativeTools(runner: runner, environment: [:])

    #expect(try await tools.run(command: .package, arguments: [], root: fixture.root) == 12)
    #expect(try Data(contentsOf: sentinel) == Data("keep me".utf8))
    let invocations = await runner.invocations
    #expect(invocations.count == 2)
    #expect(invocations.last?.executable.path == "/usr/bin/swift")
    #expect(invocations.last?.arguments == ["build", "--product", "Rook", "--configuration", "release"])
    let entries = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
    #expect(entries == ["Rook.app"])
}

@Test func sourceScanRejectsNetworkProcessAndCoreBridges() throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }

    for (target, source) in [
        ("RookApp", "let session = URLSession.shared"),
        ("RookApp", "let process = Process ()"),
        ("RookApp", "import RookVerification"),
        ("RookCore", "let connection: NWConnection? = nil"),
        ("RookCore", "import RookTooling"),
        ("RookCore", "let process = Process()"),
        ("RookCore", "let clipboard = NSPasteboard.general"),
        ("RookCore", "let workspace = NSWorkspace.shared"),
        ("RookCore", "import RookSculpture"),
        ("RookSculpture", "let session = URLSession.shared"),
        ("RookSculpture", "import RookRendering"),
        ("RookRendering", "let process = Process()"),
        ("RookRendering", "import RookApp"),
    ] {
        let file = fixture.root.appendingPathComponent("Sources/\(target)/Forbidden.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: ToolingError.self) { try SourceBoundaries.validateSources(in: fixture.root) }
        try FileManager.default.removeItem(at: file)
    }

    let toolSource = fixture.root.appendingPathComponent("Sources/RookTooling/Development.swift")
    try FileManager.default.createDirectory(
        at: toolSource.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "let process = Process()".write(to: toolSource, atomically: true, encoding: .utf8)
    try SourceBoundaries.validateSources(in: fixture.root)
}

@Test func entitlementCheckRequiresExactlyTheSandboxAndUserSelectedKeys() throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }
    let path = fixture.entitlements.path
    let sandbox = "com.apple.security.app-sandbox"
    let readWrite = "com.apple.security.files.user-selected.read-write"
    try SourceBoundaries.validateEntitlements(in: fixture.root)
    try SourceBoundaries.validateEntitlements(entitlementsData(format: .binary), path: path)

    let refusals: [(Data, String)] = try [
        (
            entitlementsData(adding: ["com.apple.security.network.client": true]),
            "Entitlements file \(path) contains unexpected key com.apple.security.network.client."
        ),
        (
            entitlementsData(removing: readWrite, adding: ["com.apple.security.files.user-selected.read-only": true]),
            "Entitlements file \(path) contains unexpected key com.apple.security.files.user-selected.read-only."
        ),
        (entitlementsData(removing: readWrite), "Entitlements file \(path) must set \(readWrite) to true."),
        (entitlementsData(removing: sandbox), "Entitlements file \(path) must set \(sandbox) to true."),
        (entitlementsData(adding: [sandbox: false]), "Entitlements file \(path) must set \(sandbox) to true."),
        (entitlementsData(adding: [readWrite: 1]), "Entitlements file \(path) must set \(readWrite) to true."),
        (entitlementsData(adding: [sandbox: "YES"]), "Entitlements file \(path) must set \(sandbox) to true."),
        (Data("fixture entitlements".utf8), "Entitlements file \(path) is not a property list dictionary."),
        (
            PropertyListSerialization.data(fromPropertyList: [sandbox, readWrite], format: .xml, options: 0),
            "Entitlements file \(path) is not a property list dictionary."
        ),
    ]
    for (data, message) in refusals {
        try data.write(to: fixture.entitlements)
        let error = #expect(throws: ToolingError.self) { try SourceBoundaries.validateEntitlements(in: fixture.root) }
        #expect(error?.description == message)
    }

    try FileManager.default.removeItem(at: fixture.entitlements)
    let missing = #expect(throws: ToolingError.self) { try SourceBoundaries.validateEntitlements(in: fixture.root) }
    #expect(missing?.description == "Required file is missing: \(path).")
}

@Test func boundaryStepRefusesAnAddedEntitlementBeforeRunningAnyTool() async throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }
    try entitlementsData(adding: ["com.apple.security.network.server": true]).write(to: fixture.entitlements)
    let runner = RecordingRunner(results: [])
    let tools = NativeTools(runner: runner, environment: [:])
    let error = await #expect(throws: ToolingError.self) {
        try await tools.run(command: .boundaries, arguments: [], root: fixture.root)
    }
    #expect(
        error?.description
            == "Entitlements file \(fixture.entitlements.path) contains unexpected key com.apple.security.network.server."
    )
    let invocations = await runner.invocations
    #expect(invocations.isEmpty)
}

@Test func productSourcesRefuseStoredDefaultsKeysOtherThanAppearance() throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }
    let allowed = #"""
        @AppStorage("rook.appearance") private var storedAppearance = AppAppearance.system.rawValue
        @AppStorage("rook.appearance", store: .standard) private var appearance = "system"
        init() { _choice = AppStorage(wrappedValue: "dark, (light)", "rook.appearance") }
        let unrelated = models.removeValue(forKey: "solar")
        let decoded = try keys.decode(Int.self, forKey: WorldJSONKey("version"))
        let thumbnail = thumbnails.object(forKey: key)
        func paint() { volume.set(1, 2, 3, glyph) }
        """#
    for target in SourceBoundaries.productTargets {
        _ = try fixture.source(allowed, in: target)
    }
    try SourceBoundaries.validateSources(in: fixture.root)

    for (target, source, key) in [
        ("RookApp", #"@AppStorage("rook.projectFolder") private var folder = """#, "rook.projectFolder"),
        ("RookApp", #"@SceneStorage("rook.camera") private var camera = """#, "rook.camera"),
        ("RookApp", #"@SwiftUI.AppStorage("rook.zoom") private var zoom = 1"#, "rook.zoom"),
        ("RookApp", #"@AppStorage("rook.appearance.backup") private var backup = """#, "rook.appearance.backup"),
        ("RookApp", #"@AppStorage(Keys.folder) private var folder = """#, "Keys.folder"),
        ("RookApp", #"@AppStorage("rook.\(name)") private var named = """#, #""rook.\(name)""#),
        ("RookApp", #"init() { _zoom = AppStorage(wrappedValue: 2, "rook.zoom") }"#, "rook.zoom"),
        ("RookApp", #"UserDefaults.standard.setValue(true, forKey: "rook.trusted")"#, "rook.trusted"),
        ("RookCore", #"UserDefaults.standard.set(path, forKey: "rook.projectFolder")"#, "rook.projectFolder"),
        ("RookCore", "let value = defaults.object(\n    forKey: \"rook.lastOpen\"\n)", "rook.lastOpen"),
        ("RookSculpture", #"let recent = defaults.stringArray(forKey: "rook.recent")"#, "rook.recent"),
        ("RookRendering", #"defaults.removeObject(forKey: "rook.cache")"#, "rook.cache"),
    ] {
        let file = try fixture.source(source, in: target, named: "Defaults.swift")
        let error = #expect(throws: ToolingError.self) { try SourceBoundaries.validateSources(in: fixture.root) }
        let description = error?.description ?? ""
        #expect(description.hasPrefix("Product source "))
        #expect(
            description.hasSuffix(
                "/Sources/\(target)/Defaults.swift uses stored defaults key \(key); only rook.appearance is allowed."
            )
        )
        try FileManager.default.removeItem(at: file)
    }

    for (target, source, token) in [
        ("RookApp", #"func save() { UserDefaults.standard.set("dark", forKey: "rook.appearance") }"#, "UserDefaults"),
        ("RookApp", #"let stored = UserDefaults.standard.string(forKey: "rook.appearance")"#, "UserDefaults"),
        (
            "RookApp",
            #"""
            private static let folderKey = "rook.projectFolder"
            func remember(_ path: String) { UserDefaults.standard.set(path, forKey: Self.folderKey) }
            """#,
            "UserDefaults"
        ),
        ("RookCore", "let dynamic = UserDefaults.standard.object(forKey: key)", "UserDefaults"),
        ("RookCore", #"UserDefaults.standard.set(path, forKey: "rook." + name)"#, "UserDefaults"),
        ("RookSculpture", #"UserDefaults.standard.register(defaults: ["rook.zoom": 2])"#, "UserDefaults"),
        (
            "RookApp",
            #"@AppStorage("rook.appearance", store: UserDefaults(suiteName: "rook")) private var theme = """#,
            "UserDefaults"
        ),
        ("RookApp", "let controller = NSUserDefaultsController.shared", "NSUserDefaults"),
        (
            "RookRendering", "CFPreferencesSetAppValue(name as CFString, value, kCFPreferencesCurrentApplication)",
            "CFPreferences"
        ),
        ("RookCore", "NSUbiquitousKeyValueStore.default.set(path, forKey: name)", "NSUbiquitousKeyValueStore"),
    ] {
        let file = try fixture.source(source, in: target, named: "Defaults.swift")
        let error = #expect(throws: ToolingError.self) { try SourceBoundaries.validateSources(in: fixture.root) }
        let description = error?.description ?? ""
        #expect(description.hasPrefix("Product source "))
        #expect(description.hasSuffix("/Sources/\(target)/Defaults.swift contains forbidden token \(token)."))
        try FileManager.default.removeItem(at: file)
    }
}

@Test func productSourcesRefuseFileWatchersAndSecurityScopedBookmarks() throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }
    let allowed = """
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        """
    for target in SourceBoundaries.productTargets {
        _ = try fixture.source(allowed, in: target)
    }
    try SourceBoundaries.validateSources(in: fixture.root)

    for (target, source, token) in [
        ("RookApp", "let stream = FSEventStreamCreate(nil, callback, nil, paths, since, 1, flags)", "FSEventStream"),
        ("RookCore", "let event = FSEventsGetCurrentEventId()", "FSEvents"),
        (
            "RookApp", "let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: file, eventMask: .all)",
            "DispatchSource.makeFileSystemObjectSource"
        ),
        ("RookSculpture", "let make = DispatchSource\n    .makeFileSystemObjectSource", "makeFileSystemObjectSource"),
        ("RookRendering", "var source: (any DispatchSourceFileSystemObject)?", "DispatchSourceFileSystemObject"),
        ("RookCore", "let filter = Int16(EVFILT_VNODE)", "EVFILT_VNODE"),
        ("RookApp", "final class FolderWatcher: NSObject, NSFilePresenter {}", "NSFilePresenter"),
        ("RookSculpture", "let coordinator = NSFileCoordinator(filePresenter: nil)", "NSFileCoordinator"),
        ("RookApp", "let bookmark = try folder.bookmarkData(options: .withSecurityScope)", "bookmarkData"),
        (
            "RookApp", "let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)",
            "resolvingBookmarkData"
        ),
        ("RookRendering", "try URL.writeBookmarkData(bookmark, to: alias)", "writeBookmarkData"),
        ("RookCore", "let data = CFURLCreateBookmarkData(nil, folder as CFURL, [], nil, nil, nil)", "BookmarkData"),
        (
            "RookSculpture", "let url = CFURLCreateByResolvingBookmarkData(nil, data, [], nil, nil, &stale, nil)",
            "BookmarkData"
        ),
    ] {
        let file = try fixture.source(source, in: target, named: "Watcher.swift")
        let error = #expect(throws: ToolingError.self) { try SourceBoundaries.validateSources(in: fixture.root) }
        let description = error?.description ?? ""
        #expect(description.hasPrefix("Product source "))
        #expect(description.hasSuffix("/Sources/\(target)/Watcher.swift contains forbidden token \(token)."))
        try FileManager.default.removeItem(at: file)
    }
}

@Test func currentRepositorySourcesAndEntitlementsPassTheBoundaryScan() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    try SourceBoundaries.validateSources(in: root)
    try SourceBoundaries.validateEntitlements(in: root)

    for name in ["RookApp.swift", "SettingsView.swift"] {
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/RookApp/\(name)"),
            encoding: .utf8
        )
        #expect(source.contains(#"@AppStorage("rook.appearance")"#))
        #expect(try SourceBoundaries.disallowedDefaultsKey(in: source) == nil)
    }
}

@Test func productDependencyGraphRejectsTransitiveToolingAndUnknownEdges() throws {
    try SourceBoundaries.validatePackage(packageDescription())
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(includeTooling: true))
    }
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(unknownEdge: true))
    }
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(coreDependsOn: "RookSculpture"))
    }
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(sculptureDependsOn: "RookApp"))
    }
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(renderingDependsOn: "RookTooling"))
    }
    #expect(throws: ToolingError.self) {
        try SourceBoundaries.validatePackage(packageDescription(omitRenderingEdge: true))
    }
}

@Test func releaseMarkerScanIncludesEmbeddedUnprintableBytes() throws {
    try ReleaseFixture.validate(Data([0, 1, 2, 255]))
    for marker in ReleaseFixture.markers {
        let binary = Data([0, 1, 2]) + Data(marker.utf8) + Data([0, 255])
        #expect(throws: ToolingError.self) { try ReleaseFixture.validate(binary) }
    }
}

@Test func repositoryInventoryRejectsPythonAndShellProgramsOutsideDependencies() throws {
    try SourceBoundaries.validateFileInventory(
        Data(
            "Sources/RookTool/main.swift\0README.md\0.build/checkouts/dependency/script.py\0.git/hooks/update.sh\0".utf8
        )
    )
    for path in ["scripts/test.py", "scripts/check.sh", "scripts/NEW.SH", "Sources/RookRendering/Shade.metal"] {
        #expect(throws: ToolingError.self) {
            try SourceBoundaries.validateFileInventory(Data(path.utf8) + Data([0]))
        }
    }
    #expect(throws: ToolingError.self) { try SourceBoundaries.validateFileInventory(Data([255, 0])) }
}

@Test func failedRepositoryInventoryCannotPassSourceBoundaries() async throws {
    let fixture = try ToolingFixture()
    defer { fixture.remove() }
    let runner = RecordingRunner(results: [
        .swiftVersion, .data(try packageDescription()), .text("git failed", status: 8),
    ])
    let tools = NativeTools(runner: runner, environment: [:])
    #expect(try await tools.run(command: .boundaries, arguments: [], root: fixture.root) == 8)
    let invocations = await runner.invocations
    let description = try #require(invocations.dropFirst().first)
    #expect(description.arguments.prefix(2) == ["package", "--scratch-path"])
    #expect(description.arguments.last == "dump-package")
    let scratch = URL(fileURLWithPath: description.arguments[2])
    #expect(scratch.lastPathComponent.hasPrefix("rook-boundaries-"))
    #expect(scratch != fixture.root.appendingPathComponent(".build"))
    #expect(!FileManager.default.fileExists(atPath: scratch.path))
    let invocation = invocations.last
    #expect(invocation?.executable.path == "/usr/bin/git")
    #expect(invocation?.arguments == ["ls-files", "--cached", "--others", "--exclude-standard", "-z"])
}

@Test func signingFailurePreservesTheExistingBundleAndRemovesStaging() async throws {
    let fixture = try ToolingFixture(includePackagingInputs: true)
    defer { fixture.remove() }
    let destination = try fixture.existingBundle()
    let sentinel = destination.appendingPathComponent("existing-content")
    try Data("keep me".utf8).write(to: sentinel)
    let runner = RecordingRunner(results: [.text("signing failed", status: 9)])

    #expect(try await AppPackaging(runner: runner).package(root: fixture.root) == 9)
    #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep me")
    let entries = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
    #expect(entries == ["Rook.app"])
    let invocations = await runner.invocations
    #expect(invocations.count == 1)
    #expect(invocations.first?.executable.path == "/usr/bin/codesign")
    #expect(
        invocations.first?.arguments.prefix(5)
            == [
                "--force", "--sign", "-", "--entitlements",
                fixture.root.appendingPathComponent("App/Rook.entitlements").path,
            ][...]
    )
}

@Test func successfulPackagingBuildsAndCopiesReleaseBeforeReplacingTheOwnedBundle() async throws {
    let fixture = try ToolingFixture(includePackagingInputs: true)
    defer { fixture.remove() }
    let destination = try fixture.existingBundle()
    let sentinel = destination.appendingPathComponent("old-content")
    try Data("old".utf8).write(to: sentinel)
    let runner = RecordingRunner(results: [
        .swiftVersion, .text("release built"), .text("signed"), .text("verified"), .text("entitlements"),
    ])
    let tools = NativeTools(runner: runner, environment: [:])

    #expect(try await tools.run(command: .package, arguments: [], root: fixture.root) == 0)
    #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    let executable = destination.appendingPathComponent("Contents/MacOS/Rook")
    let packagedData = try Data(contentsOf: executable)
    let debugData = try Data(contentsOf: fixture.root.appendingPathComponent(".build/debug/Rook"))
    #expect(packagedData == Data("release executable".utf8))
    #expect(packagedData != debugData)
    #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/Resources").path))
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(".build/debug/Rook_RookApp.bundle").path
        )
    )
    #expect(try Data(contentsOf: destination.appendingPathComponent("Contents/Info.plist")) == fixture.information)
    let invocations = await runner.invocations
    #expect(invocations.count == 5)
    #expect(invocations[1].executable.path == "/usr/bin/swift")
    #expect(invocations[1].arguments == ["build", "--product", "Rook", "--configuration", "release"])
    #expect(invocations[1].directory == fixture.root)
    #expect(invocations.suffix(3).map(\.executable.path) == Array(repeating: "/usr/bin/codesign", count: 3))
    #expect(invocations[3].arguments.prefix(2) == ["--verify", "--strict"])
    #expect(invocations[4].arguments.prefix(3) == ["--display", "--entitlements", "-"])
}

@Test func packagingDoesNotFallBackToDebugWhenReleaseIsMissing() async throws {
    let fixture = try ToolingFixture(includePackagingInputs: true)
    defer { fixture.remove() }
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(".build/release/Rook"))
    let runner = RecordingRunner(results: [])

    await #expect(throws: ToolingError.self) {
        try await AppPackaging(runner: runner).package(root: fixture.root)
    }
    #expect(await runner.invocations.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("dist/Rook.app").path))
    let debugData = try Data(contentsOf: fixture.root.appendingPathComponent(".build/debug/Rook"))
    #expect(debugData == Data("debug decoy".utf8))
}

@Test func packagingRefusesUnrelatedBundlesAndSymbolicLinkDestinations() async throws {
    let fixture = try ToolingFixture(includePackagingInputs: true)
    defer { fixture.remove() }
    let destination = try fixture.existingBundle(identifier: "unrelated.application")
    let runner = RecordingRunner(results: [])

    await #expect(throws: ToolingError.self) {
        try await AppPackaging(runner: runner).package(root: fixture.root)
    }
    #expect(await runner.invocations.isEmpty)
    try FileManager.default.removeItem(at: destination)
    try FileManager.default.createSymbolicLink(
        at: destination,
        withDestinationURL: fixture.root.appendingPathComponent("App")
    )
    await #expect(throws: ToolingError.self) {
        try await AppPackaging(runner: runner).package(root: fixture.root)
    }
    #expect(await runner.invocations.isEmpty)
}

private actor RecordingRunner: CommandRunning {
    private var results: [CommandResult]
    private(set) var invocations: [CommandInvocation] = []

    init(results: [CommandResult]) { self.results = results }

    func run(_ invocation: CommandInvocation) throws -> CommandResult {
        invocations.append(invocation)
        guard !results.isEmpty else { throw ToolingError.missingFile("unexpected invocation") }
        return results.removeFirst()
    }
}

private extension CommandResult {
    static func text(_ text: String, status: Int32 = 0) -> Self {
        Self(status: status, output: Data(text.utf8), error: Data())
    }

    static var swiftVersion: Self {
        .text("swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)\n")
    }

    static func data(_ output: Data) -> Self {
        Self(status: 0, output: output, error: Data())
    }
}

private struct ToolingFixture {
    let root: URL
    let information: Data

    init(includePackagingInputs: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rook-tooling-test-\(UUID().uuidString)")
        information = try Self.propertyList(identifier: "labs.corvid.rook")
        for target in SourceBoundaries.productTargets {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Sources/\(target)"),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App"),
            withIntermediateDirectories: true
        )
        try entitlementsData().write(to: entitlements)
        guard includePackagingInputs else { return }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".build/debug"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".build/release"),
            withIntermediateDirectories: true
        )
        try Data("debug decoy".utf8).write(to: root.appendingPathComponent(".build/debug/Rook"))
        try Data("release executable".utf8).write(to: root.appendingPathComponent(".build/release/Rook"))
        try information.write(to: root.appendingPathComponent("App/Info.plist"))
    }

    var entitlements: URL { root.appendingPathComponent("App/Rook.entitlements") }

    /// Writes a product source file and returns its path.
    func source(_ text: String, in target: String, named name: String = "Boundary.swift") throws -> URL {
        let file = root.appendingPathComponent("Sources/\(target)/\(name)")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func existingBundle(identifier: String = "labs.corvid.rook") throws -> URL {
        let bundle = root.appendingPathComponent("dist/Rook.app")
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        try Self.propertyList(identifier: identifier).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        return bundle
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func propertyList(identifier: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Rook"],
            format: .xml,
            options: 0
        )
    }
}

/// Returns entitlement property list bytes that start from the app's two current keys.
private func entitlementsData(
    removing removed: String? = nil,
    adding added: [String: Any] = [:],
    format: PropertyListSerialization.PropertyListFormat = .xml
) throws -> Data {
    var values: [String: Any] = [
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
    ]
    if let removed { values.removeValue(forKey: removed) }
    values.merge(added) { _, new in new }
    return try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
}

private func packageDescription(
    includeTooling: Bool = false,
    unknownEdge: Bool = false,
    coreDependsOn: String? = nil,
    sculptureDependsOn: String? = nil,
    renderingDependsOn: String? = nil,
    omitRenderingEdge: Bool = false
) throws -> Data {
    let targets: [[String: Any]] = SourceBoundaries.productTargets.map { name in
        let dependencies: [[String: Any]]
        switch name {
        case "RookApp":
            dependencies = ["RookCore", "RookSculpture", "RookRendering"].map { ["byName": [$0, NSNull()]] }
        case "RookRendering":
            let names = (omitRenderingEdge ? [] : ["RookSculpture"]) + (renderingDependsOn.map { [$0] } ?? [])
            dependencies = names.map { ["byName": [$0, NSNull()]] }
        case "RookSculpture":
            dependencies =
                [["product": ["ThreeMD", "3md", NSNull()]]]
                + (sculptureDependsOn.map { [["byName": [$0, NSNull()]]] } ?? [])
        case "RookCore" where includeTooling:
            dependencies = [["target": ["RookTooling", NSNull()]]]
        case "RookCore" where unknownEdge:
            dependencies = [["futureDependency": ["RookTooling", NSNull()]]]
        case "RookCore":
            dependencies = coreDependsOn.map { [["byName": [$0, NSNull()]]] } ?? []
        default:
            dependencies = []
        }
        return ["name": name, "dependencies": dependencies]
    }
    return try JSONSerialization.data(withJSONObject: ["targets": targets])
}
