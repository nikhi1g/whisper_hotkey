import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class PreservationCheckerTests: XCTestCase {
    func testProtectedTermMissingFromFinalTextIsReported() {
        let request = makeRequest(
            rawText: "Wire the FastAPI endpoint",
            protectedTerms: ["FastAPI"]
        )
        let result = makeResult(finalText: "Wire the endpoint")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, ["FastAPI"])
        XCTAssertFalse(report.pass)
    }

    func testPreservedTokensProducePassingReport() {
        let request = makeRequest(
            rawText: "Wire the FastAPI endpoint",
            protectedTerms: ["FastAPI"]
        )
        let result = makeResult(finalText: "Wire the FastAPI endpoint now")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, [])
        XCTAssertTrue(report.pass)
    }

    func testAutoProtectsURLsCodeSpansAndNumbers() {
        let request = makeRequest(
            rawText: "Deploy to https://example.com/app then run `defer cleanup()` "
                + "and set the limit to 42% or 3.14."
        )
        let result = makeResult(finalText: "Deploy to the site then run the cleanup and set the limit.")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(
            report.issues,
            ["3.14", "42", "42%", "defer cleanup()", "https://example.com/app"]
        )
        XCTAssertFalse(report.pass)
    }

    func testPreservedAutoProtectedTokensProducePassingReport() {
        let request = makeRequest(
            rawText: "Deploy to https://example.com/app then run `defer cleanup()` "
                + "and set the limit to 42% or 3.14."
        )
        let result = makeResult(
            finalText: "Deploy to https://example.com/app then run `defer cleanup()` "
                + "and set the limit to 42% or 3.14."
        )
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, [])
        XCTAssertTrue(report.pass)
    }

    func testURLTrailingPunctuationIsTrimmedFromProtectedToken() {
        let request = makeRequest(rawText: "See https://example.com, then continue.")
        let result = makeResult(finalText: "See https://example.com then continue")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, [])
        XCTAssertTrue(report.pass)
    }

    func testIssuesAreDeduplicatedAndSorted() {
        let request = makeRequest(
            rawText: "apple",
            protectedTerms: ["zebra", "apple", "zebra"]
        )
        let result = makeResult(finalText: "")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, ["apple", "zebra"])
    }

    func testOverlappingProtectedAndAutoProtectedTokensDeduplicate() {
        let request = makeRequest(rawText: "Use 3.14", protectedTerms: ["3.14"])
        let result = makeResult(finalText: "Use a constant")
        let report = PreservationChecker.report(request, result)
        XCTAssertEqual(report.issues, ["3.14"])
    }

    // MARK: - AutoSendGate

    func testGatePassesWhenLowRiskNoUnresolvedAndReportPasses() {
        let result = makeResult(risk: .low, unresolvedSpans: [])
        let report = PreservationReport(issues: [], pass: true)
        XCTAssertTrue(AutoSendGate.evaluate(result, report))
    }

    func testGateFailsOnMediumOrHighRisk() {
        let passingReport = PreservationReport(issues: [], pass: true)
        XCTAssertFalse(AutoSendGate.evaluate(makeResult(risk: .medium), passingReport))
        XCTAssertFalse(AutoSendGate.evaluate(makeResult(risk: .high), passingReport))
    }

    func testGateFailsOnUnresolvedSpans() {
        let result = makeResult(risk: .low, unresolvedSpans: ["unclear phrase"])
        let report = PreservationReport(issues: [], pass: true)
        XCTAssertFalse(AutoSendGate.evaluate(result, report))
    }

    func testGateFailsWhenReportDoesNotPass() {
        let result = makeResult(risk: .low)
        let failingReport = PreservationReport(issues: ["FastAPI"], pass: false)
        XCTAssertFalse(AutoSendGate.evaluate(result, failingReport))
    }

    func testGateCombinationWithPreservationChecker() {
        let request = makeRequest(
            rawText: "Set the FastAPI timeout to 30 seconds",
            protectedTerms: ["FastAPI"]
        )
        let cleanResult = makeResult(finalText: "Set the FastAPI timeout to 30 seconds")
        let cleanReport = PreservationChecker.report(request, cleanResult)
        XCTAssertTrue(AutoSendGate.evaluate(cleanResult, cleanReport))

        let droppedTermResult = makeResult(finalText: "Set the API timeout to 30 seconds")
        let droppedTermReport = PreservationChecker.report(request, droppedTermResult)
        XCTAssertFalse(AutoSendGate.evaluate(droppedTermResult, droppedTermReport))
    }

    private func makeRequest(
        rawText: String,
        protectedTerms: [String] = []
    ) -> PostProcessRequest {
        PostProcessRequest(
            rawText: rawText,
            profile: .clarity,
            locale: "en-US",
            context: PostProcessContext(),
            protectedTerms: protectedTerms
        )
    }

    private func makeResult(
        finalText: String = "hello",
        risk: MeaningChangeRisk = .low,
        unresolvedSpans: [String] = []
    ) -> PostProcessResult {
        PostProcessResult(
            finalText: finalText,
            intent: "",
            unresolvedSpans: unresolvedSpans,
            explicitCorrections: [],
            meaningChangeRisk: risk
        )
    }
}
