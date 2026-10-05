import Foundation

/// Resource policy for an in-memory composition, independent of each definition's document policy.
public struct DocumentCompositionLimits: Equatable, Sendable {
    /// Maximum number of unique named definitions, including entries unused by the root.
    public let maximumDefinitions: Int
    /// Maximum total reference records across all definitions; repeated targets count separately.
    public let maximumReferences: Int
    /// Maximum nodes on any reference path, counting the starting definition itself.
    public let maximumDepth: Int
    /// Maximum summed canonical UTF-8 source bytes, counting each named definition once.
    public let maximumDefinitionBytes: Int
    /// Maximum conceptual traversal occurrences from any entry, counting repeated shared references.
    public let maximumTraversalOccurrences: Int
    /// Maximum encoded profile bytes and decoded profile text bytes, enforced by the composition codec.
    public let maximumProfileBytes: Int
    /// Maximum opaque attribute pairs allowed on one reference record.
    public let maximumReferenceAttributes: Int
    /// Maximum summed UTF-8 key and value bytes allowed on one reference record.
    public let maximumReferenceAttributeBytes: Int

    /// Bounded defaults; callers may lower any limit but cannot raise the absolute ceilings.
    public static let standard = DocumentCompositionLimits(defaults: ())

    /// Creates a policy within the standard absolute ceilings; all bounds may be lowered.
    ///
    /// Definitions, depth, source bytes, occurrences and profile bytes require positive bounds.
    /// Reference records and reference attribute counts or bytes may be zero.
    /// - Throws: `DocumentCompositionError.invalidLimits` naming a bound outside its supported range.
    public init(
        maximumDefinitions: Int = 1_024,
        maximumReferences: Int = 16_384,
        maximumDepth: Int = 64,
        maximumDefinitionBytes: Int = 16 * 1_024 * 1_024,
        maximumTraversalOccurrences: Int = 1_000_000,
        maximumProfileBytes: Int = 20 * 1_024 * 1_024,
        maximumReferenceAttributes: Int = 64,
        maximumReferenceAttributeBytes: Int = 16 * 1_024
    ) throws {
        let values = [
            ("maximumDefinitions", maximumDefinitions, 1, 1_024),
            ("maximumReferences", maximumReferences, 0, 16_384),
            ("maximumDepth", maximumDepth, 1, 64),
            ("maximumDefinitionBytes", maximumDefinitionBytes, 1, 16 * 1_024 * 1_024),
            ("maximumTraversalOccurrences", maximumTraversalOccurrences, 1, 1_000_000),
            ("maximumProfileBytes", maximumProfileBytes, 1, 20 * 1_024 * 1_024),
            ("maximumReferenceAttributes", maximumReferenceAttributes, 0, 64),
            ("maximumReferenceAttributeBytes", maximumReferenceAttributeBytes, 0, 16 * 1_024),
        ]
        for (name, value, minimum, maximum) in values {
            guard (minimum...maximum).contains(value) else {
                throw DocumentCompositionError.invalidLimits(name)
            }
        }
        self.maximumDefinitions = maximumDefinitions
        self.maximumReferences = maximumReferences
        self.maximumDepth = maximumDepth
        self.maximumDefinitionBytes = maximumDefinitionBytes
        self.maximumTraversalOccurrences = maximumTraversalOccurrences
        self.maximumProfileBytes = maximumProfileBytes
        self.maximumReferenceAttributes = maximumReferenceAttributes
        self.maximumReferenceAttributeBytes = maximumReferenceAttributeBytes
    }

    private init(defaults: Void) {
        maximumDefinitions = 1_024
        maximumReferences = 16_384
        maximumDepth = 64
        maximumDefinitionBytes = 16 * 1_024 * 1_024
        maximumTraversalOccurrences = 1_000_000
        maximumProfileBytes = 20 * 1_024 * 1_024
        maximumReferenceAttributes = 64
        maximumReferenceAttributeBytes = 16 * 1_024
    }
}

/// Invalid composition structure or an exceeded resource policy. Cancellation remains `CancellationError`.
public enum DocumentCompositionError: Error, Equatable, Sendable, LocalizedError {
    case invalidLimits(String)
    case invalidID(String)
    case duplicateID(String)
    case missingRoot(String)
    case missingTarget(from: String, target: String)
    case cycle(String)
    case tooManyDefinitions
    case tooManyReferences
    case depthExceeded
    case definitionBytesExceeded
    case traversalOccurrencesExceeded
    case referenceAttributesExceeded
    case profileBytesExceeded
    case invalidProfile(String)
    case unsupportedProfile(String)

    /// A human-readable description of the invalid graph, profile or resource policy.
    public var errorDescription: String? {
        switch self {
        case .invalidLimits(let name): "Invalid composition limit: \(name)."
        case .invalidID(let id):
            "Invalid composition ID: \(id). Use 1–64 ASCII letters, digits, underscores or hyphens."
        case .duplicateID(let id): "The composition defines \(id) more than once."
        case .missingRoot(let id): "The root definition \(id) is missing."
        case .missingTarget(let source, let target): "Definition \(source) references missing definition \(target)."
        case .cycle(let id): "The composition contains a reference cycle at \(id)."
        case .tooManyDefinitions: "The composition exceeds its definition limit."
        case .tooManyReferences: "The composition exceeds its reference-record limit."
        case .depthExceeded: "The composition exceeds its reference-depth limit."
        case .definitionBytesExceeded: "The composition exceeds its total unique definition-source limit."
        case .traversalOccurrencesExceeded: "A definition's reference traversal exceeds its occurrence limit."
        case .referenceAttributesExceeded: "Reference attributes exceed their count or UTF-8 byte limit."
        case .profileBytesExceeded: "The composition profile exceeds its encoded byte limit."
        case .invalidProfile(let detail): "Invalid composition profile: \(detail)."
        case .unsupportedProfile(let schema): "Unsupported composition profile: \(schema)."
        }
    }
}
