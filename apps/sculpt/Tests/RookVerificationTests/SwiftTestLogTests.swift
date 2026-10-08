import Foundation
import RookVerification
import Testing

private let verificationStart: String = "◇ Test run started.\n↳ Testing Library Version: 1902\n"
private let verificationSummary: String = "✔ Test run with 121 tests in 0 suites passed after 2.259 seconds.\n"

@Test internal func completeSwiftTestingRunIsAcceptedWithTypedSummary() throws {
    let result = SwiftTestLog.assess(
        verificationStart + "✔ Test work() passed after 0.001 seconds.\n" + verificationSummary,
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.passed)
    #expect(result.issues.isEmpty)
    let summary = try #require(result.successfulSummaries.last)
    #expect(summary.tests == 121)
    #expect(summary.suites == 0)
    #expect(summary.durationSeconds == 2.259)
    #expect(summary.line == 4)
    let encoded = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(TestLogAssessment.self, from: encoded) == result)
    let receipt = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(receipt["passed"] as? Bool == true)
    #expect(receipt["reasons"] as? [String] == [])
}

@Test internal func recordedIssuesAndMissingSummaryAreBothRejected() {
    let result = SwiftTestLog.assess(
        verificationStart
            + "✘ Test work() recorded an issue at Example.swift:7:1: Expectation failed: false\n"
            + "✘ Test work() failed after 1.0 seconds with 1 issue.\n",
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.passed == false)
    #expect(result.failureLines.map(\.line) == [3, 4])
    #expect(result.issues == [.recordedFailures, .missingSummary])
}

@Test internal func incompleteRunWithoutFailureCannotPass() {
    let result = SwiftTestLog.assess(
        verificationStart + "◇ Test work() started.\n✔ Test other() passed after 0.001 seconds.\n",
        upstreamExitCode: 0
    )
    #expect(result.issues == [.missingSummary])
}

@Test internal func xctestZeroAloneCannotPass() {
    let result = SwiftTestLog.assess(
        "Test Suite 'All tests' passed at 2026-10-03.\n"
            + " Executed 0 tests, with 0 failures (0 unexpected) in 0.001 seconds\n",
        upstreamExitCode: 0
    )
    #expect(result.issues == [.missingSummary])
}

@Test internal func ansiUnicodeAndCIFormattingAreAccepted() {
    let log =
        "verify\tRun verify lane\t2026-10-03T15:28:34Z "
        + "\u{001B}]0;synthetic-title\u{0007}\u{001B}[32m"
        + "✔️ Test run with 121 tests in 0 suites passed after 2.259 seconds.\u{001B}[0m\r\n"
    let result = SwiftTestLog.assess(log, upstreamExitCode: 0, expectedTests: 121)
    #expect(result.passed)
    #expect(result.successfulSummaries.first?.text.contains("\u{001B}") == false)
}

@Test internal func failureWordsInsidePassingTestNamesAreNotIssues() {
    let result = SwiftTestLog.assess(
        verificationStart
            + "✔ Test failedLoadDoesNotEnableAnEmptyOverwrite() passed after 0.187 seconds.\n"
            + verificationSummary,
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.passed)
    #expect(result.failureLines.isEmpty)
}

@Test internal func upstreamFailureCannotBeHiddenBySuccessfulSummary() {
    let result = SwiftTestLog.assess(
        verificationStart + verificationSummary,
        upstreamExitCode: 9,
        expectedTests: 121
    )
    #expect(result.upstreamExitCode == 9)
    #expect(result.issues == [.upstreamFailure(exitCode: 9)])
}

@Test internal func earlierIssueCannotBeHiddenBySuccessfulSummary() {
    let result = SwiftTestLog.assess(
        verificationStart + "✘ Test work() recorded an issue at Example.swift:7:1\n" + verificationSummary,
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.issues == [.recordedFailures])
}

@Test internal func earlierSummaryCannotHideALaterUnfinishedRun() {
    let result = SwiftTestLog.assess(
        verificationStart + verificationSummary + verificationStart + "◇ Test later() started.\n",
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.issues == [.incompleteRun])
}

@Test internal func zeroSwiftTestingCountIsRejected() {
    let result = SwiftTestLog.assess(
        "✔ Test run with 0 tests passed after 0.001 seconds.\n",
        upstreamExitCode: 0
    )
    #expect(result.issues == [.zeroTests])
}

@Test internal func explicitExpectedCountIsEnforcedWithoutAProductCountPin() {
    let mismatch = SwiftTestLog.assess(verificationSummary, upstreamExitCode: 0, expectedTests: 122)
    #expect(mismatch.issues == [.unexpectedCount(expected: 122, actual: 121)])
    #expect(SwiftTestLog.assess(verificationSummary, upstreamExitCode: 0).passed)
    let invalid = SwiftTestLog.assess(verificationSummary, upstreamExitCode: 0, expectedTests: 0)
    #expect(invalid.issues.contains(.invalidExpectedCount(0)))
}

@Test internal func xctestFailureIsRejectedEvenWithSwiftTestingSuccess() {
    let result = SwiftTestLog.assess(
        "Test Case '-[Example testWork]' failed (0.001 seconds).\n" + verificationSummary,
        upstreamExitCode: 0,
        expectedTests: 121
    )
    #expect(result.issues == [.recordedFailures])
}
