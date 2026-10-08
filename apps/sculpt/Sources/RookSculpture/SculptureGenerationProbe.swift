import Foundation

#if canImport(Darwin)
import os
#else
import Synchronization
#endif

/// Notes every built-in example builder and generator that runs inside a probe scope, so tests can show that
/// listing the gallery builds nothing and that opening one entry builds only that entry.
/// Production code installs no recorder, so each hook reads one task-local value and returns.
internal enum SculptureGenerationProbe {
    /// The recorder for the current task and its child tasks, or nil outside a probe scope.
    @TaskLocal internal static var recorder: SculptureGenerationRecorder?

    /// Records that a builder or generator ran, or that the cached voxel catalog was read.
    /// - Parameter name: The gallery identity being built, such as `character-orb` or `math-terrain-256`,
    ///   or `SculptureExamples.all` for a read of the cached voxel catalog.
    internal static func record(_ name: @autoclosure () -> String) {
        guard let recorder else { return }
        recorder.record(name())
    }
}

/// The names recorded inside one probe scope, in the order they ran.
internal final class SculptureGenerationRecorder: Sendable {
    // MARK: - Properties

    // OSAllocatedUnfairLock is macOS 13 and matches the app's macOS 14 target.
    // Linux unit tests use Synchronization.Mutex, which is not available on macOS 14.
    #if canImport(Darwin)
    private let storage = OSAllocatedUnfairLock(initialState: [String]())
    #else
    private let storage = Mutex<[String]>([])
    #endif

    /// Every name recorded so far.
    internal var names: [String] {
        storage.withLock { $0 }
    }

    // MARK: - Initializers

    internal init() {}

    // MARK: - Internal Methods

    /// Appends one name. Child tasks of a probe scope may record concurrently.
    /// - Parameter name: The builder or generator that ran.
    internal func record(_ name: String) {
        storage.withLock { $0.append(name) }
    }
}
