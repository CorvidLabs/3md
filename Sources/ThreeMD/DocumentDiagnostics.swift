import Foundation

/// Inspection can stop at a caller's ceiling without implying that the remaining content was checked.
public struct DocumentDiagnosticReport: Equatable, Codable, Sendable {
    /// Issues collected in deterministic source or graph order.
    public let diagnostics: [DocumentDiagnostic]
    /// Inspection stopped at a ceiling; remaining content was not fully inspected.
    public let isTruncated: Bool
    /// Creates an inspection result, retaining whether its scope was bounded early.
    public init(diagnostics: [DocumentDiagnostic], isTruncated: Bool = false) {
        self.diagnostics = diagnostics
        self.isTruncated = isTruncated
    }
}

/// Additive value and source diagnostics. Existing parser errors and grammar remain unchanged.
public enum DocumentDiagnostics {
    /// Bounded parsing preserves actual parser line evidence and reports no invented location.
    public static func inspect(
        source: String,
        limits: DocumentEditLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentDiagnosticReport {
        try DocumentStorageCancellation.check()
        guard source.utf8.count <= limits.maximumDiagnosticBytes else {
            throw EditingFailure.make(.payloadLimit, "Diagnostic source exceeds its byte budget.", path: "source")
        }
        do {
            let document = try DocumentStorageCodec.decode(Data(source.utf8), limits: documentLimits)
            return try inspect(document, limits: limits, documentLimits: documentLimits)
        } catch let error as DocumentEditError {
            throw error
        } catch let error as DocumentStorageError {
            if case .invalidText(let parseError) = error {
                return .init(diagnostics: [parseFailure(parseError)])
            }
            return .init(diagnostics: [
                .init(code: .invalidDocument, message: error.localizedDescription, path: "source")
            ])
        }
    }

    /// Reports supplied identities and duplicate coordinates in source order within explicit work ceilings.
    /// Missing IDs are valid legacy content; adoption is always an explicit separate operation.
    public static func inspect(
        _ document: Document,
        limits: DocumentEditLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentDiagnosticReport {
        try DocumentStorageCancellation.check()
        guard document.planes.count <= documentLimits.maximumPlanes else {
            throw EditingFailure.make(
                .payloadLimit,
                "Diagnostic plane count exceeds the document policy.",
                path: "planes"
            )
        }
        var budget = EditingPayloadBudget(maximumBytes: limits.maximumDiagnosticBytes)
        try budget.document(document)
        var diagnostics: [DocumentDiagnostic] = []
        var identities: Set<String> = []
        var positions: Set<Double> = []
        for (index, plane) in document.planes.enumerated() {
            try DocumentStorageCancellation.check()
            if diagnostics.count == limits.maximumDiagnostics {
                return .init(diagnostics: diagnostics, isTruncated: true)
            }
            if let id = plane.stableID {
                let path = "planes[\(index)].attributes[3md-id]"
                if !DocumentIdentity.isValid(id) {
                    diagnostics.append(
                        .init(
                            code: .invalidIdentity,
                            message: "Plane identity must be a safe nonempty ASCII ID.",
                            path: path
                        )
                    )
                } else if !identities.insert(id).inserted {
                    diagnostics.append(
                        .init(
                            code: .duplicateIdentity,
                            message: "Plane identity is already used in this document.",
                            path: path
                        )
                    )
                }
            }
            if diagnostics.count == limits.maximumDiagnostics {
                return .init(diagnostics: diagnostics, isTruncated: true)
            }
            if !plane.z.isFinite || plane.x?.isFinite == false || plane.y?.isFinite == false {
                diagnostics.append(
                    .init(
                        code: .invalidDocument,
                        message: "Plane coordinates must be finite.",
                        path: "planes[\(index)]"
                    )
                )
            } else if !positions.insert(plane.z).inserted {
                diagnostics.append(
                    .init(
                        code: .duplicatePosition,
                        message: "Plane position is already used.",
                        path: "planes[\(index)].z"
                    )
                )
            }
        }
        if diagnostics.count == limits.maximumDiagnostics { return .init(diagnostics: diagnostics, isTruncated: true) }
        do { try DocumentStorageCodec.validate(document, limits: documentLimits) } catch {
            try EditingFailure.propagateCancellation(error)
            // Specific position diagnostics already explain that validation failure.
            if !diagnostics.contains(where: { $0.code == .duplicatePosition || $0.code == .invalidDocument }) {
                diagnostics.append(.init(code: .invalidDocument, message: error.localizedDescription))
            }
        }
        return .init(diagnostics: diagnostics)
    }

    /// Reports identities within a fully validated composition, retaining owner and reference paths.
    public static func inspect(
        _ composition: DocumentComposition,
        limits: DocumentEditLimits = .standard,
        compositionLimits: DocumentCompositionLimits = .standard,
        documentLimits: DocumentDecodeLimits = .standard
    ) throws -> DocumentDiagnosticReport {
        try DocumentStorageCancellation.check()
        // Validate caller-lowered graph policies and charge source work before collecting diagnostics.
        _ = try DocumentComposition(
            rootID: composition.rootID,
            entries: composition.entries,
            limits: compositionLimits,
            documentLimits: documentLimits
        )
        var budget = EditingPayloadBudget(maximumBytes: limits.maximumDiagnosticBytes)
        try budget.charge(composition.rootID)
        for entry in composition.entries {
            try budget.charge(entry.id); try budget.document(entry.document)
            for reference in entry.references {
                try budget.charge(reference.targetID); try budget.attributes(reference.attributes)
            }
        }
        var diagnostics: [DocumentDiagnostic] = []
        for (entryIndex, entry) in composition.entries.enumerated() {
            try DocumentStorageCancellation.check()
            let report = try inspect(entry.document, limits: limits, documentLimits: documentLimits)
            for diagnostic in report.diagnostics {
                guard diagnostics.count < limits.maximumDiagnostics else {
                    return .init(diagnostics: diagnostics, isTruncated: true)
                }
                diagnostics.append(
                    .init(
                        code: diagnostic.code,
                        message: diagnostic.message,
                        severity: diagnostic.severity,
                        sourceLine: diagnostic.sourceLine,
                        path: "entries[\(entryIndex)].document" + (diagnostic.path.map { ".\($0)" } ?? "")
                    )
                )
            }
            if report.isTruncated { return .init(diagnostics: diagnostics, isTruncated: true) }
            var ids: Set<String> = []
            for (index, reference) in entry.references.enumerated() {
                try DocumentStorageCancellation.check()
                guard diagnostics.count < limits.maximumDiagnostics else {
                    return .init(diagnostics: diagnostics, isTruncated: true)
                }
                guard let id = reference.stableID else { continue }
                let path = "entries[\(entryIndex)].references[\(index)].attributes[3md-id]"
                if !DocumentIdentity.isValid(id) {
                    diagnostics.append(
                        .init(
                            code: .invalidIdentity,
                            message: "Reference identity must be a safe nonempty ASCII ID.",
                            path: path
                        )
                    )
                } else if !ids.insert(id).inserted {
                    diagnostics.append(
                        .init(
                            code: .duplicateIdentity,
                            message: "Reference identity is already used by this owner.",
                            path: path
                        )
                    )
                }
            }
        }
        return .init(diagnostics: diagnostics)
    }

    /// Wraps an existing parser failure without manufacturing missing source evidence.
    public static func parseFailure(_ error: ParseError) -> DocumentDiagnostic {
        .init(code: .parseFailure, message: error.localizedDescription, sourceLine: error.line, path: "source")
    }

    internal static func compositionError(_ error: DocumentCompositionError, entries: [DocumentEntry])
        -> DocumentEditError
    {
        let path: String
        switch error {
        case .missingRoot: path = "rootID"
        case .missingTarget(let owner, let target):
            if let entryIndex = entries.firstIndex(where: { $0.id == owner }),
                let referenceIndex = entries[entryIndex].references.firstIndex(where: { $0.targetID == target })
            {
                path = "entries[\(entryIndex)].references[\(referenceIndex)].targetID"
            } else {
                path = "entries"
            }
        case .cycle(let id), .invalidID(let id), .duplicateID(let id):
            path = entries.firstIndex(where: { $0.id == id }).map { "entries[\($0)]" } ?? "rootID"
        default: path = "entries"
        }
        return EditingFailure.make(.invalidComposition, error.localizedDescription, path: path)
    }
}
