import Foundation
import XCTest
@testable import WhisperHotkeyCore

final class PostProcessingContractTests: XCTestCase {
    func testDocumentedLimitConstantsMatchTheContract() {
        XCTAssertEqual(PostProcessLimits.maxRawTextLength, 4_000)
        XCTAssertEqual(PostProcessLimits.maxFinalTextLength, 8_000)
        XCTAssertEqual(PostProcessLimits.maxAlternatives, 8)
        XCTAssertEqual(PostProcessLimits.maxUncertainSpans, 32)
        XCTAssertEqual(PostProcessLimits.maxProtectedTerms, 128)
        XCTAssertEqual(PostProcessLimits.maxGlossaryTerms, 64)
        XCTAssertEqual(PostProcessLimits.maxCorrections, 32)
    }

    func testValidateRequestRejectsOverLengthRawText() {
        let request = makeRequest(rawText: String(repeating: "a", count: 4_001))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.raw_text",
            actual: 4_001,
            maximum: PostProcessLimits.maxRawTextLength
        )
    }

    func testValidateRequestAcceptsRawTextAtTheBound() throws {
        let request = makeRequest(rawText: String(repeating: "a", count: 4_000))
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))
    }

    func testValidateRequestRejectsOverCountAlternatives() {
        let request = makeRequest(alternatives: Array(repeating: "alt", count: 9))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.alternatives",
            actual: 9,
            maximum: PostProcessLimits.maxAlternatives
        )
    }

    func testValidateRequestRejectsOverLengthAlternative() {
        let request = makeRequest(alternatives: [String(repeating: "b", count: 201)])
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.alternatives[0]",
            actual: 201,
            maximum: 200
        )
    }

    func testValidateRequestRejectsOverCountUncertainSpans() {
        let request = makeRequest(uncertainSpans: Array(repeating: "span", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.uncertain_spans",
            actual: 33,
            maximum: PostProcessLimits.maxUncertainSpans
        )
    }

    func testValidateRequestRejectsOverCountProtectedTerms() {
        let request = makeRequest(protectedTerms: Array(repeating: "term", count: 129))
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "request.protected_terms",
            actual: 129,
            maximum: PostProcessLimits.maxProtectedTerms
        )
    }

    func testValidateRequestRejectsOverCountGlossaryTerms() {
        let request = makeRequest(
            context: PostProcessContext(glossary: Array(repeating: "word", count: 65))
        )
        assertLimitExceeded(
            try PostProcessLimits.validateRequest(request),
            field: "context.glossary",
            actual: 65,
            maximum: PostProcessLimits.maxGlossaryTerms
        )
    }

    func testValidateResultRejectsOverLengthFinalText() {
        let result = makeResult(finalText: String(repeating: "c", count: 8_001))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.final_text",
            actual: 8_001,
            maximum: PostProcessLimits.maxFinalTextLength
        )
    }

    func testValidateResultRejectsOverLengthIntent() {
        let result = makeResult(intent: String(repeating: "i", count: 401))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.intent",
            actual: 401,
            maximum: 400
        )
    }

    func testValidateResultRejectsOverCountCorrections() {
        let result = makeResult(explicitCorrections: Array(repeating: "fix", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.explicit_corrections",
            actual: 33,
            maximum: PostProcessLimits.maxCorrections
        )
    }

    func testValidateResultRejectsOverLengthCorrection() {
        let result = makeResult(explicitCorrections: [String(repeating: "x", count: 161)])
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.explicit_corrections[0]",
            actual: 161,
            maximum: 160
        )
    }

    func testValidateResultRejectsOverCountUnresolvedSpans() {
        let result = makeResult(unresolvedSpans: Array(repeating: "unclear", count: 33))
        assertLimitExceeded(
            try PostProcessLimits.validateResult(result),
            field: "result.unresolved_spans",
            actual: 33,
            maximum: 32
        )
    }

    func testValidRequestAndResultAtMaximumBoundsPass() throws {
        let request = makeRequest(
            rawText: String(repeating: "a", count: 4_000),
            alternatives: Array(repeating: String(repeating: "b", count: 200), count: 8),
            uncertainSpans: Array(repeating: String(repeating: "c", count: 80), count: 32),
            protectedTerms: Array(repeating: String(repeating: "d", count: 80), count: 128),
            context: PostProcessContext(glossary: Array(repeating: String(repeating: "e", count: 80), count: 64))
        )
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))

        let result = makeResult(
            finalText: String(repeating: "f", count: 8_000),
            intent: String(repeating: "g", count: 400),
            unresolvedSpans: Array(repeating: String(repeating: "h", count: 160), count: 32),
            explicitCorrections: Array(repeating: String(repeating: "i", count: 160), count: 32)
        )
        XCTAssertNoThrow(try PostProcessLimits.validateResult(result))
    }

    func testEmptyRequestAndResultPass() throws {
        let request = makeRequest(rawText: "")
        XCTAssertNoThrow(try PostProcessLimits.validateRequest(request))
        let result = makeResult(finalText: "", intent: "")
        XCTAssertNoThrow(try PostProcessLimits.validateResult(result))
    }

    private func makeRequest(
        rawText: String = "hello",
        alternatives: [String] = [],
        uncertainSpans: [String] = [],
        protectedTerms: [String] = [],
        context: PostProcessContext = PostProcessContext()
    ) -> PostProcessRequest {
        PostProcessRequest(
            rawText: rawText,
            profile: .clarity,
            locale: "en-US",
            context: context,
            alternatives: alternatives,
            uncertainSpans: uncertainSpans,
            protectedTerms: protectedTerms
        )
    }

    private func makeResult(
        finalText: String = "hello",
        intent: String = "",
        unresolvedSpans: [String] = [],
        explicitCorrections: [String] = []
    ) -> PostProcessResult {
        PostProcessResult(
            finalText: finalText,
            intent: intent,
            unresolvedSpans: unresolvedSpans,
            explicitCorrections: explicitCorrections,
            meaningChangeRisk: .low
        )
    }

    private func assertLimitExceeded(
        _ expression: @autoclosure () throws -> Void,
        field: String,
        actual: Int,
        maximum: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case PostProcessContractError.limitExceeded(
                let errorField,
                let errorActual,
                let errorMaximum
            ) = error else {
                XCTFail("expected limitExceeded, got \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(errorField, field, file: file, line: line)
            XCTAssertEqual(errorActual, actual, file: file, line: line)
            XCTAssertEqual(errorMaximum, maximum, file: file, line: line)
        }
    }
}
