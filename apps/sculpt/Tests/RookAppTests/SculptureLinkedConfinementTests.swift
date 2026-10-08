import Darwin
import Foundation
import RookSculpture
import Testing

@testable import RookApp

@Suite("Linked file confinement", .serialized)
@MainActor
struct SculptureLinkedConfinementTests {
    // MARK: - Symbolic links

    @Test func aSymbolicLinkFolderComponentIsRefusedNamingTheFile() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("real/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try FileManager.default.createSymbolicLink(
            at: project.url("models"),
            withDestinationURL: project.url("real")
        )
        let failure = try await onlyFailure(project, links: ["A": "../models/oak.3md"])
        #expect(failure.file == "models/oak.3md")
        #expect(failure.reason.contains("symbolic link \"models\""))

        let reader = SculptureProjectReader(folderPath: SculptureProjectFolder(project.folder).path)
        await #expect(throws: SculptureLinkedError.self) { try await reader.read("models/oak.3md", maximumBytes: 64) }
        let direct = try await reader.read("real/oak.3md", maximumBytes: 4_096)
        #expect(try direct == Data(contentsOf: project.url("real/oak.3md")))
    }

    @Test func aSymbolicLinkFileIsRefusedEvenWhenItPointsInsideOrOutsideTheFolder() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        let outside = project.container.appendingPathComponent("outside.3md")
        try LinkedAppProject.voxel("Outside", glyph: 64).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: project.url("models/alias.3md"),
            withDestinationURL: project.url("models/oak.3md")
        )
        try FileManager.default.createSymbolicLink(at: project.url("models/escape.3md"), withDestinationURL: outside)
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../models/alias.3md", "B": "../models/escape.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(repair.failures.map(\.file) == ["models/alias.3md", "models/escape.3md"])
        #expect(repair.failures.allSatisfy { $0.reason.hasPrefix("is a symbolic link.") })
    }

    @Test func aScalarThatJoinsASeparatorToItsNameCannotCarryOneOpenThroughASymbolicLink() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let outside = project.container.appendingPathComponent("private/Models")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try LinkedAppProject.voxel("Outside", glyph: 64).write(to: outside.appendingPathComponent("oak.3md"))
        // U+0600 is a Prepend scalar, so as Swift characters "evil\u{0600}/Models" is one cluster with no separator.
        let link = "evil\u{0600}"
        try FileManager.default.createSymbolicLink(
            at: project.url(link),
            withDestinationURL: outside.deletingLastPathComponent()
        )
        let reader = SculptureProjectReader(folderPath: SculptureProjectFolder(project.folder).path)
        await #expect(throws: SculptureLinkedError.self) {
            try await reader.read("\(link)/Models/oak.3md", maximumBytes: 4_096)
        }
        // A combining mark after a separator, through a link that points inside the folder, joins the same way.
        try project.write("real/\u{0301}oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try FileManager.default.createSymbolicLink(at: project.url("models"), withDestinationURL: project.url("real"))
        await #expect(throws: SculptureLinkedError.self) {
            try await reader.read("models/\u{0301}oak.3md", maximumBytes: 4_096)
        }
        #expect(await reader.bytesRead == 0, "Nothing is read through either symbolic link.")

        let failure = try await onlyFailure(project, links: ["A": "../\(link)/Models/oak.3md"])
        #expect(failure.file == "\(link)/Models/oak.3md")
        #expect(failure.reason.contains("symbolic link \"\(link)\""))
    }

    @Test func aRootReachedThroughASymbolicLinkFolderIsReadFromItsRealLocationOnly() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        try FileManager.default.createSymbolicLink(
            at: project.url("shortcut"),
            withDestinationURL: project.url("scenes")
        )
        // The open panel may hand back a path through a link; the root is compared and read by its real path.
        let session = try await LinkedAppProject.session(
            root: project.url("shortcut/main.3md"),
            folder: project.folder
        )
        #expect(session.rootPath == "scenes/main.3md" && session.draft != nil)
        #expect(root.lastPathComponent == session.fileName)
    }

    // MARK: - Hidden items, hard links and aliases

    @Test func hiddenFoldersAndFilesAreRefusedNamingTheFile() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write(".private/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try project.write("models/.stone.3md", LinkedAppProject.voxel("Stone", glyph: 64))
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../.private/oak.3md", "B": "../models/.stone.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(repair.failures.map(\.file) == [".private/oak.3md", "models/.stone.3md"])
        #expect(repair.failures[0].reason.contains("\".private\""))
        #expect(repair.failures[1].reason.contains("\".stone.3md\""))
        #expect(repair.failures.allSatisfy { $0.reason.contains("Hidden files and folders are not read.") })

        // A root inside a hidden folder is refused too.
        let hiddenRoot = try project.write(
            ".drafts/main.3md",
            LinkedAppProject.linked("Draft", files: ["A": "../models/.stone.3md"])
        )
        let draftSession = try await LinkedAppProject.session(root: hiddenRoot, folder: project.folder)
        #expect(draftSession.repair?.failures.map(\.file) == [".drafts/main.3md"])
    }

    @Test func aLeadingPeriodWithACombiningMarkIsStillHidden() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        // No precomposed form exists, so ".\u{0301}" stays one Swift character that does not equal ".".
        let mark = ".\u{0301}"
        try project.write("\(mark)private/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try project.write("models/\(mark)stone.3md", LinkedAppProject.voxel("Stone", glyph: 64))
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked(
                "Main hall",
                files: ["A": "../\(mark)private/oak.3md", "B": "../models/\(mark)stone.3md"]
            )
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(repair.failures.map(\.file) == ["\(mark)private/oak.3md", "models/\(mark)stone.3md"])
        #expect(repair.failures.allSatisfy { $0.reason.contains("Hidden files and folders are not read.") })
        #expect(session.draft == nil)
    }

    @Test func aHardLinkedFileIsRefusedNamingTheFile() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let oak = try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try FileManager.default.linkItem(at: oak, to: project.url("models/copy.3md"))
        let failure = try await onlyFailure(project, links: ["A": "../models/oak.3md"])
        #expect(failure.file == "models/oak.3md" && failure.reason.contains("more than one hard link"))
    }

    @Test func aSecondSpellingOfAFileAlreadyReadIsRefusedWhereTheVolumeAllowsIt() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        let caseSensitive =
            try project.folder.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames ?? true
        guard !caseSensitive else {
            // On a case-sensitive volume the second spelling is a different, missing file.
            let failure = try await onlyFailure(project, links: ["A": "../models/oak.3md", "B": "../Models/Oak.3md"])
            #expect(failure.file == "Models/Oak.3md" && failure.reason.contains("not in the project folder"))
            return
        }
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../models/oak.3md", "B": "../Models/Oak.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        let alias = try #require(repair.failures.first { $0.file == "Models/Oak.3md" })
        #expect(alias.reason == "names the same file as models/oak.3md. Use one spelling for each linked file.")

        // One reader identifies files by device and inode across reads.
        let reader = SculptureProjectReader(folderPath: SculptureProjectFolder(project.folder).path)
        _ = try await reader.read("models/oak.3md", maximumBytes: 4_096)
        _ = try await reader.read("models/oak.3md", maximumBytes: 4_096)
        await #expect(throws: SculptureLinkedError.self) {
            try await reader.read("MODELS/OAK.3md", maximumBytes: 4_096)
        }
    }

    // MARK: - Reads

    @Test func readsAreBoundedRegularAndReportMissingFilesSoTheLinkingFileIsNamed() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let data = try LinkedAppProject.voxel("Oak", glyph: 35)
        try project.write("models/oak.3md", data)
        try FileManager.default.createDirectory(at: project.url("models/folder.3md"), withIntermediateDirectories: true)
        let reader = SculptureProjectReader(folderPath: SculptureProjectFolder(project.folder).path)

        #expect(try await reader.read("models/oak.3md", maximumBytes: data.count) == data)
        await #expect(
            throws: SculptureLinkedError.limit(
                kind: .definitionBytes,
                maximum: SculptureLinkedResolver.maximumDefinitionBytes,
                path: "models/oak.3md"
            )
        ) {
            try await reader.read("models/oak.3md", maximumBytes: data.count - 1)
        }
        await #expect(throws: SculptureLinkedError.file(path: "models/folder.3md", reason: "is not a regular file.")) {
            try await reader.read("models/folder.3md", maximumBytes: 4_096)
        }
        do {
            _ = try await reader.read("models/missing.3md", maximumBytes: 4_096)
            Issue.record("A missing file was read")
        } catch let error as POSIXError {
            #expect(error.code == .ENOENT)
        }
        do {
            _ = try await reader.read("models/oak.3md/inner.3md", maximumBytes: 4_096)
            Issue.record("A path below a file was read")
        } catch let error as POSIXError {
            #expect(error.code == .ENOENT)
        }
        for invalid in ["", "/models/oak.3md", "models//oak.3md", "models/../oak.3md"] {
            await #expect(throws: SculptureLinkedError.self) { try await reader.read(invalid, maximumBytes: 4_096) }
        }
        #expect(await reader.bytesRead == data.count)

        let failure = try await onlyFailure(project, links: ["A": "../models/missing.3md"])
        #expect(failure.file == "models/missing.3md")
        #expect(failure.reason == "is not in the project folder. scenes/main.3md links it.")
    }

    @Test func theFolderScopeIsHeldOnlyForTheAttemptAndCancellationPublishesNothing() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.writeStandard()
        let folder = SculptureProjectFolder(project.folder)
        let attempt = Task { try await folder.attempt(rootPath: "scenes/main.3md", diagnose: true) }
        attempt.cancel()
        await #expect(throws: CancellationError.self) { try await attempt.value }
        guard case .resolved(let resolution) = try await folder.attempt(rootPath: "scenes/main.3md", diagnose: false)
        else {
            Issue.record("The standard project did not resolve")
            return
        }
        #expect(resolution.rootPath == "scenes/main.3md" && resolution.resolvedPaths.count == 4)
    }

    // MARK: - Helpers

    /// Opens a root at `scenes/main.3md` with `links` and returns its single repair failure.
    private func onlyFailure(
        _ project: LinkedAppProject,
        links: [Character: String]
    ) async throws -> SculptureLinkedRepairFailure {
        let root = try project.write("scenes/main.3md", LinkedAppProject.linked("Main hall", files: links))
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(session.draft == nil)
        let failures = repair.failures.filter { $0.link != nil }
        #expect(failures.count == 1, "Expected one failing link, found \(repair.failures)")
        return try #require(failures.first)
    }
}
