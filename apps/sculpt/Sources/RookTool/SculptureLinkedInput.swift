import Foundation
import RookSculpture
import ThreeMD

/// Linked roots in explicit-file commands. A linked composition reads its models from other files in its project
/// folder, and the app opens it with that folder. RookTool reads only the files a command names, so it refuses a
/// linked root by name instead of reporting a generic decode failure, and never follows a `3md-files` link.
internal enum SculptureLinkedInput {
    // MARK: - Internal Methods

    /// Refuses a readable linked root, detected by content with the shared codec.
    /// - Parameters:
    ///   - data: The bytes of a file a command names.
    ///   - file: The file name used in the refusal.
    /// - Throws: `SculptureLinkedInputError.needsProjectFolder` for a readable linked root.
    internal static func refuseLinkedRoot(_ data: Data, file: String) throws {
        guard SculptureLinkedCodec.isLinked(data) else { return }
        throw SculptureLinkedInputError.needsProjectFolder(file)
    }

    /// Refuses a binary container that declares the linked schema. Call it only after another decoder has rejected
    /// the bytes: it decodes a binary container again through the shared linked codec, and ignores other failures.
    /// - Parameters:
    ///   - data: The rejected bytes of a file a command names.
    ///   - file: The file name used in the refusal.
    /// - Throws: `SculptureLinkedInputError.binaryLinkedRoot`, or `CancellationError` when cancelled.
    internal static func refuseBinaryLinkedRoot(_ data: Data, file: String) throws {
        guard DocumentStorageCodec.isBinary(data) else { return }
        do {
            _ = try SculptureLinkedCodec.decode(data)
        } catch SculptureLinkedError.binaryLinkedRoot {
            throw SculptureLinkedInputError.binaryLinkedRoot(file)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return
        }
    }

    /// Restates the shared scene reader's linked-root refusals naming `file`.
    /// - Parameters:
    ///   - error: An error from `SculptureSceneReader` or the portable codec.
    ///   - file: The file name used in the refusal.
    /// - Returns: A named linked-root refusal, or `error` unchanged.
    internal static func naming(_ error: any Error, file: String) -> any Error {
        switch error as? SculptureLinkedError {
        case .needsProjectFolder?: SculptureLinkedInputError.needsProjectFolder(file)
        case .binaryLinkedRoot?: SculptureLinkedInputError.binaryLinkedRoot(file)
        default: error
        }
    }
}

/// A linked root named by an explicit-file command.
internal enum SculptureLinkedInputError: Error, Equatable, LocalizedError, Sendable {
    /// A readable linked root, which only the app reads with its project folder.
    case needsProjectFolder(String)
    /// A binary container declaring the linked schema, which nothing reads.
    case binaryLinkedRoot(String)

    /// A readable explanation naming the file.
    internal var errorDescription: String? {
        switch self {
        case .needsProjectFolder(let file):
            "\(file) is a linked composition and needs its project folder, because its models are separate files "
                + "listed in 3md-files. Open it in Sculpt.3md and choose that folder. RookTool reads only the files "
                + "a command names and does not read linked files."
        case .binaryLinkedRoot(let file):
            "\(file): \(SculptureLinkedError.binaryLinkedRoot.localizedDescription)"
        }
    }
}
