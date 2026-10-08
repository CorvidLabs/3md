import Foundation
import Observation
import RookSculpture

/// A linked composition opened with its project folder. The folder grant and root location live only in this
/// session's memory. The resolved composition is shown view-only; nothing in the session writes a file.
@MainActor
@Observable
internal final class SculptureLinkedSession: Identifiable {
    // MARK: - Properties

    internal let id = UUID()
    /// The root file chosen with Open. Its contents are read again through the confined reader.
    internal let rootURL: URL
    internal private(set) var folder: SculptureProjectFolder
    /// The root's NFC path inside `folder`.
    internal private(set) var rootPath: String
    /// The view-only composition, present after the first successful resolution.
    internal private(set) var draft: SculptureCompositionDraft?
    /// The latest successful resolution, with the digest of every file it read.
    internal private(set) var resolution: SculptureLinkedResolution?
    /// Failing links found when no scene has resolved yet.
    internal private(set) var repair: SculptureLinkedRepair?
    internal private(set) var isResolving = false
    /// The latest reload or folder refusal, naming the project file. A shown scene stays unchanged.
    internal private(set) var error: String?
    internal private(set) var notice: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    /// The root's file name for messages.
    internal var fileName: String { rootURL.lastPathComponent }
    internal var title: String { draft?.title ?? repair?.title ?? fileName }
    internal var canReload: Bool { !isResolving }


    // MARK: - Initializers

    /// Grants `folder` to this session after checking that `rootURL` lies inside it.
    /// - Throws: `SculptureLinkedError.outsideProject` when the root is not inside the folder.
    internal init(rootURL: URL, folder: URL) throws {
        let project = SculptureProjectFolder(folder)
        rootPath = try project.projectPath(of: rootURL)
        self.rootURL = rootURL
        self.folder = project
    }


    // MARK: - Internal Methods

    /// Resolves the root again on demand in a detached task. A newer request or `cancel()` makes an older result
    /// stale. A failure keeps any shown scene, and a reload never marks the session changed. The latest failure
    /// stays until a result replaces it, so a cancelled reload leaves the status as it was; progress takes priority
    /// in the views meanwhile.
    @discardableResult
    internal func reload() -> Task<Void, Never> {
        cancel()
        let identifier = UUID()
        generation = identifier
        isResolving = true
        let folder = folder
        let rootPath = rootPath
        let diagnose = draft == nil
        let task = Task { [weak self] in
            let outcome: SculptureLinkedAttempt
            do {
                outcome = try await folder.attempt(rootPath: rootPath, diagnose: diagnose)
            } catch {
                guard let self, self.generation == identifier else { return }
                self.isResolving = false
                self.task = nil
                return
            }
            guard let self, self.generation == identifier, !Task.isCancelled else { return }
            self.isResolving = false
            self.task = nil
            self.receive(outcome)
        }
        self.task = task
        return task
    }

    /// Replaces the folder grant when the root lies inside `url`, then resolves again. Otherwise the current grant,
    /// scene and repair stay as they are and the refusal names the root.
    internal func chooseFolder(_ url: URL) {
        let project = SculptureProjectFolder(url)
        do {
            let path = try project.projectPath(of: rootURL)
            cancel()
            folder = project
            rootPath = path
            reload()
        } catch {
            self.error = Self.message(for: error, file: fileName)
        }
    }

    /// Stops any resolution in progress. Its result is never published.
    internal func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isResolving = false
    }

    /// Whether plain Open must ask for the project folder of the file it read.
    internal static func requiresProjectFolder(_ error: any Error) -> Bool {
        (error as? SculptureLinkedError) == .needsProjectFolder
    }

    /// What plain Open does after reading `file` failed: ask for a linked root's project folder, or report.
    internal static func openFailure(_ error: any Error, file: String) -> SculptureOpenFailure {
        if requiresProjectFolder(error) { return .requestProjectFolder }
        if error is SculptureLinkedError { return .report(message(for: error, file: file)) }
        return .report(SculpturePortableDiagnostic.message(error))
    }

    /// A message for an open or folder failure. Linked refusals that carry no file name are prefixed with `file`.
    internal static func message(for error: any Error, file: String) -> String {
        let message = SculptureDiagnosticMessage.describe(error)
        switch error as? SculptureLinkedError {
        case .needsProjectFolder, .binaryLinkedRoot, .outsideProject, .invalid: return "\(file): \(message)"
        default: return message
        }
    }

    /// Opens a linked root with the folder the person chose. A missing folder means the request was cancelled and
    /// nothing opens; cancelling the calling task also opens nothing.
    internal static func open(root: URL, folder: URL?) async -> SculptureLinkedOpenOutcome {
        guard let folder else { return .cancelled }
        let session: SculptureLinkedSession
        do { session = try SculptureLinkedSession(rootURL: root, folder: folder) } catch {
            return .refused(message(for: error, file: root.lastPathComponent))
        }
        let resolution = session.reload()
        await withTaskCancellationHandler {
            await resolution.value
        } onCancel: {
            resolution.cancel()
        }
        guard !Task.isCancelled, session.draft != nil || session.repair != nil else {
            session.cancel()
            return .cancelled
        }
        return .opened(session)
    }


    // MARK: - Private Methods

    private func receive(_ outcome: SculptureLinkedAttempt) {
        switch outcome {
        case .resolved(let resolution):
            self.resolution = resolution
            if let draft {
                draft.showLinked(resolution.composition, modelPaths: resolution.modelPaths)
            } else {
                draft = .linkedView(resolution.composition, modelPaths: resolution.modelPaths)
            }
            repair = nil
            error = nil
            notice =
                "Resolved \(SculptureInsertionWording.count(resolution.resolvedPaths.count, "linked file")) "
                + "from \(folder.name)."
        case .failed(let message, let repair):
            if draft != nil {
                error = message
            } else {
                // The repair list replaces an earlier folder refusal.
                error = nil
                self.repair =
                    repair
                    ?? SculptureLinkedRepair(
                        title: fileName,
                        rootPath: rootPath,
                        failures: [.init(link: nil, file: rootPath, reason: message)],
                        checkedLinks: 0,
                        uncheckedLinks: 0
                    )
            }
        }
    }
}

/// The next step after plain Open could not decode a file.
internal enum SculptureOpenFailure: Equatable, Sendable {
    /// The file is a readable linked root. Open asks for its project folder and opens nothing until one is chosen.
    case requestProjectFolder
    /// Any other failure, explained in one message.
    case report(String)
}

/// What opening a linked root produced.
internal enum SculptureLinkedOpenOutcome {
    /// The folder request or the resolution was cancelled. Nothing opened.
    case cancelled
    /// The folder was refused, for example because it does not contain the root. Nothing opened.
    case refused(String)
    /// A session with a resolved scene or a repair view.
    case opened(SculptureLinkedSession)
}

/// What the repair view offers beside Close. Its buttons read this value, so the offer is checked in-process.
internal struct SculptureLinkedRepairActions: Equatable, Sendable {
    // MARK: - Properties

    /// Choose Folder regrants the project folder. It waits while a resolution runs.
    internal let canChooseFolder: Bool
    /// Reload resolves the root again. It waits while a resolution runs.
    internal let canReload: Bool


    // MARK: - Internal Methods

    /// The actions `session` offers now.
    @MainActor
    internal static func actions(for session: SculptureLinkedSession) -> Self {
        Self(canChooseFolder: !session.isResolving, canReload: session.canReload)
    }
}

/// One failing file, with the root link that leads to it when one link does.
internal struct SculptureLinkedRepairFailure: Identifiable, Equatable, Sendable {
    // MARK: - Properties

    /// The root's link character, or nil for a failure of the root itself or of the whole graph.
    internal let link: String?
    /// The project path of the failing file.
    internal let file: String
    internal let reason: String

    internal var id: String { [link ?? "", file, reason].joined(separator: "\u{1F}") }


    // MARK: - Initializers

    internal init(link: String?, file: String, reason: String) {
        self.link = link
        self.file = file
        self.reason = reason
    }

    /// Names the file a resolution error is about, and why it failed.
    internal init(_ error: any Error, rootPath: String, link: String?) {
        self.link = link
        switch error as? SculptureLinkedError {
        case .file(let path, let reason):
            file = path
            self.reason = reason
        case .missingFile(let path, let linkedFrom):
            file = path
            reason = "is not in the project folder. \(linkedFrom) links it."
        case .invalidPath(let link, let linkedFrom):
            file = linkedFrom
            reason = "links \"\(link)\", which is not a valid path inside the project folder."
        case .unsupportedChild(let path, let kind):
            file = path
            reason =
                "is \(kind). Link readable ascii-sculpture-1 voxel files, uncompressed binary voxel files or other "
                + "linked compositions."
        case .limit(let kind, let maximum, let path):
            file = path
            reason = "reaches the linked composition limit of \(kind.describe(maximum))."
        case .cycle(let paths):
            file = paths.first ?? rootPath
            reason = "is part of a cycle: \(paths.joined(separator: " → "))."
        case .needsProjectFolder, .binaryLinkedRoot, .outsideProject, .invalid, nil:
            file = rootPath
            reason = SculptureDiagnosticMessage.describe(error)
        }
    }
}

/// What the repair view shows when a linked root does not resolve at open. Writing nothing, it lists each root link
/// that fails on its own, plus any failure that only the whole graph reaches.
internal struct SculptureLinkedRepair: Equatable, Sendable {
    // MARK: - Properties

    /// At most this many root links are checked one by one.
    internal static let maximumProbes = SculptureLinkedResolver.maximumFiles

    /// The root's title, or its file name when the root itself cannot be read.
    internal let title: String
    internal let rootPath: String
    internal let failures: [SculptureLinkedRepairFailure]
    /// Root links resolved on their own.
    internal let checkedLinks: Int
    /// Root links left unchecked because the probe or byte budget ran out.
    internal let uncheckedLinks: Int


    // MARK: - Internal Methods

    /// Resolves each root link on its own, in glyph order, through the same confined reader as the failed attempt.
    /// Probes stop after `maximumProbes` links or one maximum definition budget of bytes.
    /// - Throws: `CancellationError` only.
    internal static func diagnose(
        rootPath: String,
        failure: any Error,
        reader: SculptureProjectReader
    ) async throws -> Self {
        let primary = SculptureLinkedRepairFailure(failure, rootPath: rootPath, link: nil)
        let root: SculptureLinkedComposition
        do {
            let data = try await reader.read(rootPath, maximumBytes: SculptureLinkedResolver.maximumDefinitionBytes)
            root = try SculptureLinkedCodec.decode(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return Self(
                title: (rootPath as NSString).lastPathComponent,
                rootPath: rootPath,
                failures: [primary],
                checkedLinks: 0,
                uncheckedLinks: 0
            )
        }
        let start = await reader.bytesRead
        let glyphs = root.files.keys.sorted()
        var failures: [SculptureLinkedRepairFailure] = []
        var checked = 0
        for glyph in glyphs {
            try Task.checkCancellation()
            let spent = await reader.bytesRead - start
            guard checked < maximumProbes, spent < SculptureLinkedResolver.maximumDefinitionBytes,
                let link = root.files[glyph]
            else { break }
            checked += 1
            let character = String(decoding: [glyph], as: UTF8.self)
            do {
                let probe = try SculptureLinkedComposition(
                    title: root.title,
                    width: 1,
                    height: 1,
                    tileSize: root.tileSize,
                    layers: [[glyph]],
                    files: [glyph: link],
                    quarterTurns: root.quarterTurns[glyph].map { [glyph: $0] } ?? [:]
                )
                _ = try await SculptureLinkedResolver.resolve(
                    rootPath: rootPath,
                    rootData: SculptureLinkedCodec.encode(probe),
                    read: reader.reader
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(SculptureLinkedRepairFailure(error, rootPath: rootPath, link: character))
            }
        }
        if !failures.contains(where: { $0.file == primary.file && $0.reason == primary.reason }) {
            failures.insert(primary, at: 0)
        }
        return Self(
            title: root.title,
            rootPath: rootPath,
            failures: failures,
            checkedLinks: checked,
            uncheckedLinks: glyphs.count - checked
        )
    }
}
