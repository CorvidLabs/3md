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

    // MARK: - Public Properties

    /// Stable machine-readable error code matching the parser error case.
    public var code: String {
        switch self {
        case .missingFrontmatter:
            return "missingFrontmatter"
        case .invalidFrontmatter:
            return "invalidFrontmatter"
        case .missingVersion:
            return "missingVersion"
        case .invalidPlaneDirective:
            return "invalidPlaneDirective"
        case .missingPlanePosition:
            return "missingPlanePosition"
        case .duplicatePlane:
            return "duplicatePlane"
        }
    }

    /// The 1-based source line associated with the error, when available.
    public var line: Int? {
        switch self {
        case .invalidPlaneDirective(let line, _), .missingPlanePosition(let line):
            return line
        case .missingFrontmatter, .invalidFrontmatter, .missingVersion, .duplicatePlane:
            return nil
        }
    }

    /// Extra case-specific detail suitable for JSON diagnostics.
    public var detail: String? {
        switch self {
        case .invalidFrontmatter(let detail), .invalidPlaneDirective(_, let detail):
            return detail
        case .duplicatePlane(let z):
            return String(z)
        case .missingFrontmatter, .missingVersion, .missingPlanePosition:
            return nil
        }
    }

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
