import Foundation

/// Assesses the Swift Testing console format without executing tests or editing logs.
public enum SwiftTestLog {
    /// The maximum raw log size accepted by the command runner.
    public static let maximumLogBytes: Int = 32 * 1024 * 1024

    /// Assesses a caller-provided log and its recorded upstream exit.
    ///
    /// Terminal control sequences are removed only for matching. An earlier
    /// successful summary cannot hide a later unfinished run or a recorded issue.
    ///
    /// - Parameters:
    ///   - text: The UTF-8 log content decoded by the caller.
    ///   - upstreamExitCode: The actual process exit recorded by the caller.
    ///   - expectedTests: An optional positive exact final test count.
    /// - Returns: Immutable typed evidence accepting or rejecting the run.
    public static func assess(
        _ text: String,
        upstreamExitCode: Int32,
        expectedTests: Int? = nil
    ) -> TestLogAssessment {
        let clean = text.replacing(
            #/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]/#,
            with: ""
        )
        let lines = clean.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var failures: [TestLogFailure] = []
        var summaries: [TestRunSummary] = []
        var lastStart: Int?

        for (offset, source) in lines.enumerated() {
            let line = String(source)
            let number = offset + 1
            if containsFailure(in: line) {
                failures.append(TestLogFailure(line: number, text: line))
            }
            if let summary = parseSummary(line, number: number) {
                summaries.append(summary)
            }
            if line.firstMatch(of: /\bTest run started\.\s*$/) != nil
                || line.firstMatch(of: /\b(?:Test|Suite) .+ started\.\s*$/) != nil
            {
                lastStart = number
            }
        }

        var issues: [TestLogIssue] = []
        if upstreamExitCode != 0 {
            issues.append(.upstreamFailure(exitCode: upstreamExitCode))
        }
        if let expectedTests, expectedTests < 1 {
            issues.append(.invalidExpectedCount(expectedTests))
        }
        if failures.isEmpty == false {
            issues.append(.recordedFailures)
        }
        if let final = summaries.last {
            if let lastStart, lastStart > final.line {
                issues.append(.incompleteRun)
            }
            if final.tests == 0 {
                issues.append(.zeroTests)
            }
            if let expectedTests, final.tests != expectedTests {
                issues.append(.unexpectedCount(expected: expectedTests, actual: final.tests))
            }
        } else {
            issues.append(.missingSummary)
        }
        return TestLogAssessment(
            upstreamExitCode: upstreamExitCode,
            expectedTests: expectedTests,
            issues: issues,
            failureLines: failures,
            successfulSummaries: summaries
        )
    }

    private static func parseSummary(_ line: String, number: Int) -> TestRunSummary? {
        guard
            let match = line.firstMatch(
                of:
                    #/
                    \bTest\x20run\x20with\x20([0-9]+)\x20tests?
                    (?:\x20in\x20([0-9]+)\x20suites?)?\x20passed\x20after\x20
                    ([0-9]+(?:\.[0-9]+)?)\x20seconds?\.\s*$
                    /#
            ),
            let tests = Int(match.output.1),
            let seconds = Double(match.output.3),
            seconds.isFinite
        else {
            return nil
        }
        let suites: Int?
        if let count = match.output.2 {
            guard let parsed = Int(count) else {
                return nil
            }
            suites = parsed
        } else {
            suites = nil
        }
        return TestRunSummary(line: number, tests: tests, suites: suites, durationSeconds: seconds, text: line)
    }

    private static func containsFailure(in line: String) -> Bool {
        line.firstMatch(of: /\brecorded an issue\b/) != nil
            || line.firstMatch(of: /\bExpectation failed:/) != nil
            || line.firstMatch(of: /\b(?:Test|Suite|Test run) .+ failed after\b/) != nil
            || line.firstMatch(of: /\bTest (?:Case|Suite) .+ failed(?:\s|\()/) != nil
            || line.firstMatch(of: /\bExecuted [0-9]+ tests?, with [1-9][0-9]* failures?\b/) != nil
            || line.firstMatch(of: /\b(?:Fatal error|Assertion failed):/) != nil
    }
}
