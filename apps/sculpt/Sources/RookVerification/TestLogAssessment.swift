/// A recorded issue or failure, with its one-based location in the test log.
public struct TestLogFailure: Codable, Equatable, Sendable {
    /// The one-based line number in the supplied log.
    public let line: Int
    /// The matching line after terminal control sequences are removed.
    public let text: String

    internal init(line: Int, text: String) {
        self.line = line
        self.text = text
    }
}

/// A successful Swift Testing summary observed in a log.
public struct TestRunSummary: Codable, Equatable, Sendable {
    /// The one-based line number of the summary.
    public let line: Int
    /// The number of completed tests reported by Swift Testing.
    public let tests: Int
    /// The optional number of completed suites.
    public let suites: Int?
    /// The elapsed seconds reported by Swift Testing.
    public let durationSeconds: Double
    /// The summary after terminal control sequences are removed.
    public let text: String

    internal init(line: Int, tests: Int, suites: Int?, durationSeconds: Double, text: String) {
        self.line = line
        self.tests = tests
        self.suites = suites
        self.durationSeconds = durationSeconds
        self.text = text
    }
}

/// A reason the supplied run cannot be accepted as successful verification.
public enum TestLogIssue: Codable, Equatable, Sendable {
    /// The caller recorded a nonzero upstream process exit.
    case upstreamFailure(exitCode: Int32)
    /// The log contains at least one recorded test issue or failure.
    case recordedFailures
    /// The log contains no successful final Swift Testing summary.
    case missingSummary
    /// Another run, suite or test started after the last successful summary.
    case incompleteRun
    /// The final successful summary reports zero completed tests.
    case zeroTests
    /// The final count differs from the caller's explicit expectation.
    case unexpectedCount(expected: Int, actual: Int)
    /// An explicit expected count must be positive.
    case invalidExpectedCount(Int)

    /// A readable explanation suitable for a command receipt.
    public var message: String {
        switch self {
        case .upstreamFailure(let exitCode):
            "upstream swift test exited \(exitCode)"
        case .recordedFailures:
            "recorded test issue/failure lines are present"
        case .missingSummary:
            "final successful Swift Testing summary is absent"
        case .incompleteRun:
            "a later Swift Testing run/test started without a final successful summary"
        case .zeroTests:
            "Swift Testing completed zero tests"
        case .unexpectedCount(let expected, _):
            "final Swift Testing count does not match expected \(expected)"
        case .invalidExpectedCount:
            "expected-tests must be positive"
        }
    }
}

/// Pure, immutable evidence from assessing a Swift Testing console log.
///
/// An XCTest success line alone cannot establish success. The assessment also
/// requires an actual upstream exit of zero, a positive Swift Testing count,
/// no recorded issues and no later unfinished run.
public struct TestLogAssessment: Codable, Equatable, Sendable {
    /// The upstream exit code supplied by the caller, never inferred from text.
    public let upstreamExitCode: Int32
    /// An optional exact final test count supplied by the caller.
    public let expectedTests: Int?
    /// All reasons the run was rejected.
    public let issues: [TestLogIssue]
    /// The issue and failure lines observed in the supplied log.
    public let failureLines: [TestLogFailure]
    /// All valid successful Swift Testing summaries, in source order.
    public let successfulSummaries: [TestRunSummary]

    /// Whether the supplied evidence satisfies the verification contract.
    public var passed: Bool {
        issues.isEmpty
    }

    /// Readable failure explanations, in the same order as issues.
    public var reasons: [String] {
        issues.map(\.message)
    }

    /// Decodes typed evidence; acceptance is always derived from its issues.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            upstreamExitCode: try values.decode(Int32.self, forKey: .upstreamExitCode),
            expectedTests: try values.decodeIfPresent(Int.self, forKey: .expectedTests),
            issues: try values.decode([TestLogIssue].self, forKey: .issues),
            failureLines: try values.decode([TestLogFailure].self, forKey: .failureLines),
            successfulSummaries: try values.decode([TestRunSummary].self, forKey: .successfulSummaries)
        )
    }

    /// Encodes typed evidence and readable acceptance fields for command receipts.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(upstreamExitCode, forKey: .upstreamExitCode)
        try values.encodeIfPresent(expectedTests, forKey: .expectedTests)
        try values.encode(issues, forKey: .issues)
        try values.encode(failureLines, forKey: .failureLines)
        try values.encode(successfulSummaries, forKey: .successfulSummaries)
        try values.encode(passed, forKey: .passed)
        try values.encode(reasons, forKey: .reasons)
    }

    internal init(
        upstreamExitCode: Int32,
        expectedTests: Int?,
        issues: [TestLogIssue],
        failureLines: [TestLogFailure],
        successfulSummaries: [TestRunSummary]
    ) {
        self.upstreamExitCode = upstreamExitCode
        self.expectedTests = expectedTests
        self.issues = issues
        self.failureLines = failureLines
        self.successfulSummaries = successfulSummaries
    }

    private enum CodingKeys: String, CodingKey {
        case upstreamExitCode
        case expectedTests
        case issues
        case failureLines
        case successfulSummaries
        case passed
        case reasons
    }
}
