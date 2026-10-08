import Foundation
import ThreeMD

/// Content-detected decoding of any native or portable scene bytes. Hosts own file access.
public enum SculptureSceneReader {
    /// Portable data is detected first, then sparse worlds, compositions, linked roots and voxel documents.
    /// The snapshot is present only for portable ThreeMD content.
    ///
    /// A readable linked root throws `SculptureLinkedError.needsProjectFolder`; resolve it with
    /// `SculptureLinkedResolver`. A binary linked root throws `SculptureLinkedError.binaryLinkedRoot`.
    public static func decode(_ data: Data) throws -> (scene: SculptureScene, snapshot: SculptureThreeMDSnapshot?) {
        try Task.checkCancellation()
        if SculptureThreeMDCodec.isPortable(data) {
            let snapshot = try SculptureThreeMDCodec.decode(data)
            return (snapshot.scene, snapshot)
        }
        if SculptureWorldCodec.isWorld(data) {
            return (.world(try SculptureWorldCodec.decode(data)), nil)
        }
        if SculptureCompositionCodec.isComposition(data) {
            return (.composition(try SculptureCompositionCodec.decode(data)), nil)
        }
        if SculptureLinkedCodec.isLinked(data) {
            throw SculptureLinkedError.needsProjectFolder
        }
        return (.voxels(try SculptureDocumentCodec.decode(data)), nil)
    }
}

/// One readable explanation for scene, storage and portable ThreeMD failures, shared by the app and tools.
public enum SculptureDiagnosticMessage {
    public static func describe(_ error: any Error) -> String {
        let diagnostic: DocumentDiagnostic?
        if let error = error as? DocumentEditError {
            diagnostic = error.diagnostic
        } else if let error = error as? SculptureThreeMDError {
            diagnostic = error.diagnostic
        } else if let error = error as? DocumentStorageError, case .invalidText(let parseError) = error {
            diagnostic = DocumentDiagnostics.parseFailure(parseError)
        } else {
            diagnostic = nil
        }
        let explanation: String
        if let diagnostic {
            let location = diagnostic.path.map { " at \($0)" } ?? ""
            let line = diagnostic.sourceLine.map { " (line \($0))" } ?? ""
            explanation = "\(diagnostic.code.rawValue)\(location)\(line): \(diagnostic.message)"
        } else {
            explanation = error.localizedDescription
        }
        if SculptureThreeMDCodec.isCapacityError(error) {
            return
                "This scene exceeds portable ThreeMD capacity. Save in its existing Sculpt format or reduce its size. \(explanation)"
        }
        return explanation
    }
}
