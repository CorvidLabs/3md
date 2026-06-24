@preconcurrency import Foundation

// MARK: - ParseError

/// Errors thrown while parsing a 3md document.
public enum ParseError: Error, LocalizedError, Sendable, Equatable {
    /// The document did not begin with a `---` frontmatter block.
    case missingFrontmatter

    /// The frontmatter was malformed.
    case invalidFrontmatter(String)

    /// The frontmatter omitted the required `3md` version key.
    case missingVersion

    /// A `@plane` directive was malformed.
    case invalidPlaneDirective(line: Int, detail: String)

    /// A `@plane` directive omitted its required `z` position.
    case missingPlanePosition(line: Int)

    /// Two planes shared the same `z` position.
    case duplicatePlane(z: Double)

    // MARK: - LocalizedError

    /// A human-readable description of the parse failure.
    public var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            return "3md documents must begin with a '---' frontmatter block."
        case .invalidFrontmatter(let detail):
            return "Invalid frontmatter: \(detail)"
        case .missingVersion:
            return "Frontmatter is missing the required '3md' version key."
        case .invalidPlaneDirective(let line, let detail):
            return "Invalid @plane directive on line \(line): \(detail)"
        case .missingPlanePosition(let line):
            return "The @plane directive on line \(line) is missing a 'z' position."
        case .duplicatePlane(let z):
            return "Two planes share the same z position: \(z)"
        }
    }
}
