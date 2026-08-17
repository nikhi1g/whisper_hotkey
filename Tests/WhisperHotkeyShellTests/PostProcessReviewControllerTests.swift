import AppKit
import XCTest
@testable import WhisperHotkeyShell
import WhisperHotkeyCore

final class PostProcessReviewControllerTests: XCTestCase {
    // MARK: - ReviewChoice key mapping

    func testEnterAndKeypadEnterMapToAcceptProcessed() {
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(forKeyCode: 36, modifiers: []),
            .acceptProcessed
        )
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(forKeyCode: 76, modifiers: []),
            .acceptProcessed
        )
    }

    func testEscapeMapsToCancel() {
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(forKeyCode: 53, modifiers: []),
            .cancel
        )
    }

    func testCommandZMapsToRestoreRaw() {
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(
                forKeyCode: 6,
                modifiers: [.command]
            ),
            .restoreRaw
        )
    }

    func testCommandShiftZStaysTheDestinationRedo() {
        XCTAssertNil(
            PostProcessReviewKeyMapping.action(
                forKeyCode: 6,
                modifiers: [.command, .shift]
            )
        )
        XCTAssertNil(
            PostProcessReviewKeyMapping.action(forKeyCode: 6, modifiers: [])
        )
    }

    func testTabMapsToCycleProfile() {
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(forKeyCode: 48, modifiers: []),
            .cycleProfile
        )
    }

    func testUnmappedKeysPassThrough() {
        XCTAssertNil(
            PostProcessReviewKeyMapping.action(forKeyCode: 0, modifiers: [])
        )
        XCTAssertNil(
            PostProcessReviewKeyMapping.action(
                forKeyCode: 48,
                modifiers: [.command]
            )
        )
    }

    func testReturnAcceptsRegardlessOfModifiersLikeExistingDictation() {
        // The dictation tap consumes Return with any modifier flags; the
        // review keeps that contract so Command-Return still accepts.
        XCTAssertEqual(
            PostProcessReviewKeyMapping.action(
                forKeyCode: 36,
                modifiers: [.command]
            ),
            .acceptProcessed
        )
    }

    // MARK: - Tab cycling order

    func testTabCyclesClarityCodingVerbatimThenClarity() {
        XCTAssertEqual(
            PostProcessReviewProfileCycle.next(after: .clarity),
            .coding
        )
        XCTAssertEqual(
            PostProcessReviewProfileCycle.next(after: .coding),
            .verbatim
        )
        XCTAssertEqual(
            PostProcessReviewProfileCycle.next(after: .verbatim),
            .clarity
        )
    }

    // MARK: - Rendering inputs

    private func preview(
        processed: PostProcessResult?,
        issues: [String] = [],
        unavailable: Bool = false
    ) -> PostProcessPreview {
        PostProcessPreview(
            rawText: "raw text",
            processed: processed,
            report: PreservationReport(issues: issues, pass: issues.isEmpty),
            profile: .clarity,
            unavailable: unavailable
        )
    }

    func testUnavailablePreviewRendersRawOnly() {
        let content = PostProcessReviewRendering.content(
            for: preview(processed: nil, unavailable: true)
        )
        XCTAssertEqual(content.rawText, "raw text")
        XCTAssertNil(content.processedText)
        XCTAssertNil(content.risk)
        XCTAssertNil(content.footerText)
        XCTAssertTrue(content.unavailable)
    }

    func testProcessedPreviewCarriesRiskAndCorrectionsFooter() {
        let result = PostProcessResult(
            finalText: "processed text",
            intent: "clarify",
            unresolvedSpans: [],
            explicitCorrections: ["colour → color"],
            meaningChangeRisk: .medium
        )
        let content = PostProcessReviewRendering.content(
            for: preview(processed: result)
        )
        XCTAssertEqual(content.processedText, "processed text")
        XCTAssertEqual(content.risk, .medium)
        XCTAssertEqual(content.riskText, "Meaning change risk: Medium")
        XCTAssertEqual(content.footerText, "Corrected: colour → color")
        XCTAssertFalse(content.unavailable)
    }

    func testMissingPreservedTokensAppearInFooter() {
        let result = PostProcessResult(
            finalText: "processed text",
            intent: "clarify",
            unresolvedSpans: [],
            explicitCorrections: [],
            meaningChangeRisk: .low
        )
        let content = PostProcessReviewRendering.content(
            for: preview(
                processed: result,
                issues: ["7.2", "api.example.com"]
            )
        )
        XCTAssertEqual(content.risk, .low)
        XCTAssertEqual(content.riskText, "Meaning change risk: Low")
        XCTAssertEqual(
            content.footerText,
            "Not preserved: 7.2, api.example.com"
        )
    }

    // MARK: - Controller delivery rules

    private func processedResult() -> PostProcessResult {
        PostProcessResult(
            finalText: "processed text",
            intent: "clarify",
            unresolvedSpans: [],
            explicitCorrections: [],
            meaningChangeRisk: .low
        )
    }

    @MainActor
    func testUnavailableEnterDeliversRestoreRawNeverAcceptProcessed() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        var delivered: [ReviewChoice] = []
        controller.present(
            preview(processed: nil, unavailable: true),
            accept: { _, choice in delivered.append(choice) },
            onProfileChange: { _ in }
        )
        XCTAssertTrue(controller.handleKeyDown(keyCode: 36, modifiers: []))
        XCTAssertEqual(delivered, [.restoreRaw])
    }

    @MainActor
    func testProcessedEnterDeliversAcceptProcessed() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        var delivered: [ReviewChoice] = []
        controller.present(
            preview(processed: processedResult()),
            accept: { _, choice in delivered.append(choice) },
            onProfileChange: { _ in }
        )
        XCTAssertTrue(controller.handleKeyDown(keyCode: 36, modifiers: []))
        XCTAssertEqual(delivered, [.acceptProcessed])
    }

    @MainActor
    func testTabCallsOnProfileChangeInCycleOrderWithoutDelivering() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        var profiles: [SemanticProfileID] = []
        var delivered: [ReviewChoice] = []
        controller.present(
            preview(processed: processedResult()),
            accept: { _, choice in delivered.append(choice) },
            onProfileChange: { profiles.append($0) }
        )
        XCTAssertTrue(controller.handleKeyDown(keyCode: 48, modifiers: []))
        XCTAssertTrue(controller.handleKeyDown(keyCode: 48, modifiers: []))
        XCTAssertTrue(controller.handleKeyDown(keyCode: 48, modifiers: []))
        XCTAssertEqual(profiles, [.coding, .verbatim, .clarity])
        XCTAssertTrue(delivered.isEmpty)
    }

    @MainActor
    func testEscapeAndCommandZDeliverCancelAndRestoreRaw() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        var delivered: [ReviewChoice] = []
        controller.present(
            preview(processed: processedResult()),
            accept: { _, choice in delivered.append(choice) },
            onProfileChange: { _ in }
        )
        XCTAssertTrue(controller.handleKeyDown(keyCode: 53, modifiers: []))
        XCTAssertEqual(delivered, [.cancel])

        delivered = []
        controller.present(
            preview(processed: processedResult()),
            accept: { _, choice in delivered.append(choice) },
            onProfileChange: { _ in }
        )
        XCTAssertTrue(
            controller.handleKeyDown(keyCode: 6, modifiers: [.command])
        )
        XCTAssertEqual(delivered, [.restoreRaw])
    }


    @MainActor
    func testKeysPassThroughWhenNothingIsPresented() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        XCTAssertFalse(controller.handleKeyDown(keyCode: 36, modifiers: []))
        XCTAssertFalse(controller.handleKeyDown(keyCode: 53, modifiers: []))
        XCTAssertFalse(controller.handleKeyDown(keyCode: 48, modifiers: []))
        XCTAssertFalse(
            controller.handleKeyDown(keyCode: 6, modifiers: [.command])
        )
    }

    @MainActor
    func testBadgeRendersUnavailableReviewState() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        controller.present(
            preview(processed: nil, unavailable: true),
            accept: { _, _ in },
            onProfileChange: { _ in }
        )
        XCTAssertEqual(badge.reviewRawTextForTesting, "raw text")
        XCTAssertNil(badge.reviewProcessedTextForTesting)
        XCTAssertEqual(
            badge.reviewStatusTextForTesting,
            "unavailable — raw shown"
        )
        XCTAssertNil(badge.reviewFooterTextForTesting)
    }

    @MainActor
    func testBadgeRendersProcessedReviewWithLowRiskAccent() {
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        controller.present(
            preview(processed: processedResult()),
            accept: { _, _ in },
            onProfileChange: { _ in }
        )
        XCTAssertEqual(badge.reviewRawTextForTesting, "raw text")
        XCTAssertEqual(badge.reviewProcessedTextForTesting, "processed text")
        XCTAssertNil(badge.reviewStatusTextForTesting)
        XCTAssertEqual(
            badge.reviewRiskColorForTesting,
            BadgeThemePalette.palette(for: BadgeTheme.defaultTheme).waveform
        )
    }

    @MainActor
    func testBadgeRendersMediumRiskAndCorrectionsInErrorRed() {
        let result = PostProcessResult(
            finalText: "processed text",
            intent: "clarify",
            unresolvedSpans: [],
            explicitCorrections: ["colour → color"],
            meaningChangeRisk: .medium
        )
        let badge = CaretBadgeController()
        let controller = PostProcessReviewController(badge: badge)
        controller.present(
            preview(processed: result),
            accept: { _, _ in },
            onProfileChange: { _ in }
        )
        XCTAssertEqual(badge.reviewRiskColorForTesting, NSColor.systemRed)
        XCTAssertEqual(
            badge.reviewFooterTextForTesting,
            "Corrected: colour → color"
        )
    }
}
